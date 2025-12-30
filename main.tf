terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Random password for K3s cluster
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "devops-final-project-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "devops-final-project-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "devops-final-project-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "devops-final-project-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Security Groups
resource "aws_security_group" "main" {
  name        = "main_security_group"
  description = "Security group for Kubernetes cluster"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kafka
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Elasticsearch
  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kibana
  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal traffic
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-final-project-sg"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "devops_lambda_s3_kafka_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "devops-lambda-role"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "devops_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.data_bucket.arn}",
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 Bucket
resource "aws_s3_bucket" "data_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name = "devops-final-project-data-bucket"
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.data_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_kafka_publisher.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Lambda Function
resource "aws_lambda_function" "s3_kafka_publisher" {
  filename         = "lambda_function.zip"
  function_name    = "s3-kafka-publisher"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("lambda_function.zip")
  runtime         = "python3.11"
  timeout         = 60

  environment {
    variables = {
      KAFKA_BOOTSTRAP_SERVERS = "${aws_instance.kubernetes_master.public_ip}:9092"
      KAFKA_TOPIC            = "s3-events"
    }
  }

  tags = {
    Name = "devops-s3-kafka-publisher"
  }

  depends_on = [aws_iam_role_policy.lambda_policy]
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_kafka_publisher.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_bucket.arn
}

# API Gateway
resource "aws_api_gateway_rest_api" "kafka_api" {
  name        = "kafka-event-api"
  description = "API Gateway for publishing events to Kafka"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.kafka_api.id
  parent_id   = aws_api_gateway_rest_api.kafka_api.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post_event" {
  rest_api_id   = aws_api_gateway_rest_api.kafka_api.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "kafka_integration" {
  rest_api_id             = aws_api_gateway_rest_api.kafka_api.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post_event.http_method
  integration_http_method = "POST"
  type                    = "HTTP"
  uri                     = "http://${aws_instance.kubernetes_master.public_ip}:8080/publish"
}

resource "aws_api_gateway_deployment" "kafka_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.kafka_api.id
  stage_name  = "prod"

  depends_on = [aws_api_gateway_integration.kafka_integration]
}

# Kubernetes Master Node
resource "aws_instance" "kubernetes_master" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.main.id]
  associate_public_ip_address = true

  user_data = <<-EOF
                #!/bin/bash
                set -e
                exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
                
                # Install K3s
                curl -sfL https://get.k3s.io | K3S_TOKEN=${random_password.k3s_token.result} sh -
                
                # Wait for K3s to be ready
                sleep 30
                
                # Install Docker for Kafka
                yum update -y
                yum install -y docker
                systemctl start docker
                systemctl enable docker
                
                # Install Docker Compose
                curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                chmod +x /usr/local/bin/docker-compose
                
                echo "Master node setup complete"
                EOF

  tags = {
    Name = "KubernetesMaster"
  }
}

# Kubernetes Worker Node
resource "aws_instance" "kubernetes_worker" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.main.id]
  associate_public_ip_address = true

  user_data = <<-EOF
                #!/bin/bash
                set -e
                exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
                MASTER_IP="${aws_instance.kubernetes_master.private_ip}"
                
                # Wait for Master API to be reachable
                while ! curl -k --output /dev/null --silent --head "https://$MASTER_IP:6443"; do
                  echo "Waiting for Master API server at $MASTER_IP:6443..."
                  sleep 5
                done

                curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" K3S_TOKEN=${random_password.k3s_token.result} sh -
                
                echo "Worker node setup complete"
                EOF

  tags = {
    Name = "KubernetesWorker"
  }

  depends_on = [aws_instance.kubernetes_master]
}
