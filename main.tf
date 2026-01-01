terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- VPC & Networking ---
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = { Name = "devops-project-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "sg" {
  name        = "devops-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow SSH, HTTP, KafkaREST, K8s"

  # SSH
  ingress { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  # Kibana
  ingress { from_port = 5601, to_port = 5601, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  # Kafka REST (for Lambda)
  ingress { from_port = 8082, to_port = 8082, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  # Internal
  ingress { from_port = 0, to_port = 0, protocol = "-1", self = true }

  egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
}

# --- EC2 Instance (K3s + Docker Compose) ---
resource "aws_instance" "master" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg.id]

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # 1. Install Tools
    yum update -y
    yum install -y docker git
    systemctl enable --now docker
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Install K3s
    curl -sfL https://get.k3s.io | sh -

    # Setup Work Directory
    mkdir -p /home/ec2-user/devops
    cd /home/ec2-user/devops

    # Get Private IP for Internal Networking
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

    # 2. Create Docker Compose for Infra (Kafka, ELK)
    # Using Docker Compose is shorter/easier for this specific stack than raw K8s manifests
    cat <<DOCKER > docker-compose.yml
    version: '3'
    services:
      zookeeper:
        image: confluentinc/cp-zookeeper:latest
        environment:
          ZOOKEEPER_CLIENT_PORT: 2181
          ZOOKEEPER_TICK_TIME: 2000
        networks: [app-net]

      kafka:
        image: confluentinc/cp-kafka:latest
        depends_on: [zookeeper]
        ports: ["9092:9092"]
        environment:
          KAFKA_BROKER_ID: 1
          KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
          # Advertise Private IP for K8s Consumers to reach
          KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://$${PRIVATE_IP}:9092
          KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
          KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
          KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
        networks: [app-net]

      kafka-rest:
        image: confluentinc/cp-kafka-rest:latest
        depends_on: [kafka]
        ports: ["8082:8082"]
        environment:
          KAFKA_REST_HOST_NAME: kafka-rest
          KAFKA_REST_BOOTSTRAP_SERVERS: kafka:29092
          KAFKA_REST_LISTENERS: http://0.0.0.0:8082
        networks: [app-net]

      elasticsearch:
        image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
        environment:
          - discovery.type=single-node
          - xpack.security.enabled=false
          - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
        ports: ["9200:9200"]
        networks: [app-net]

      kibana:
        image: docker.elastic.co/kibana/kibana:8.11.0
        depends_on: [elasticsearch]
        ports: ["5601:5601"]
        environment:
          ELASTICSEARCH_HOSTS: http://elasticsearch:9200
        networks: [app-net]

      logstash:
        image: docker.elastic.co/logstash/logstash:8.11.0
        depends_on: [elasticsearch, kafka]
        volumes:
          - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
        networks: [app-net]

    networks:
      app-net:
    DOCKER

    # Logstash Config
    cat <<CONFIG > logstash.conf
    input {
      kafka {
        bootstrap_servers => "kafka:29092"
        topics => ["s3-events", "api-events", "app-logs"]
        codec => "json"
        group_id => "logstash"
      }
    }
    filter {
      # Escape Terraform Template syntax
      mutate { add_field => { "source_ip" => "%%{host}" } }
    }
    output {
      elasticsearch {
        hosts => ["elasticsearch:9200"]
        index => "logs-%%{+YYYY.MM.dd}"
      }
    }
    CONFIG

    # Start Infra
    /usr/local/bin/docker-compose up -d

    # 3. Deploy K8s Workload (Kafka Consumer)
    cat <<K8S > consumer.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: kafka-consumer
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: consumer
      template:
        metadata:
          labels:
            app: consumer
        spec:
          containers:
          - name: python-consumer
            image: python:3.9-slim
            command: ["/bin/sh", "-c"]
            args:
              - |
                pip install kafka-python &&
                python -u -c '
                from kafka import KafkaConsumer, KafkaProducer
                import json, time, os

                # Connect to Kafka on Host IP
                BROKER = "$${PRIVATE_IP}:9092"

                # Consumer for events
                consumer = KafkaConsumer(
                    "s3-events", "api-events",
                    bootstrap_servers=[BROKER],
                    value_deserializer=lambda x: json.loads(x.decode("utf-8")),
                    group_id="k8s-workers"
                )

                # Producer for Logs (to satisfy Observability requirement)
                producer = KafkaProducer(
                    bootstrap_servers=[BROKER],
                    value_serializer=lambda v: json.dumps(v).encode("utf-8")
                )

                print(f"Starting Consumer on {BROKER}...")

                for msg in consumer:
                    # Log to stdout (K8s)
                    print(f"Consumed: {msg.value}")

                    # Log to Kafka "app-logs" for ELK
                    log_entry = {
                        "level": "INFO",
                        "message": "Processed event",
                        "event": msg.value,
                        "component": "k8s-consumer"
                    }
                    producer.send("app-logs", log_entry)
                '
    K8S

    # Apply K8s
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    kubectl apply -f consumer.yaml
  EOF

  tags = { Name = "DevOps-Master" }
}

# --- S3 Bucket ---
resource "random_string" "bucket_suffix" {
  length = 8
  special = false
  upper = false
}

resource "aws_s3_bucket" "b" {
  bucket = "devops-project-data-${random_string.bucket_suffix.result}"
  force_destroy = true
}

# --- Lambda & API Gateway ---
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "func" {
  filename      = "lambda_function.zip"
  function_name = "devops-event-handler"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout       = 10

  environment {
    variables = {
      KAFKA_REST_URL = "http://${aws_instance.master.public_ip}:8082"
    }
  }
}

# IAM
resource "aws_iam_role" "iam_for_lambda" {
  name = "devops_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 Trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.b.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.func.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3]
}

resource "aws_lambda_permission" "allow_s3" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.func.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.b.arn
}

# API Gateway (HTTP) Trigger
resource "aws_apigatewayv2_api" "api" {
  name          = "devops-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.func.invoke_arn
}

resource "aws_apigatewayv2_route" "post" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /event"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "allow_api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.func.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/event"
}
