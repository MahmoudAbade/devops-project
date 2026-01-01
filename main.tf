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

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.key_name}-${random_string.suffix.result}"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  content         = tls_private_key.pk.private_key_pem
  filename        = "${aws_key_pair.deployer.key_name}.pem"
  file_permission = "0400"
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

  # Kafka REST Proxy
  ingress {
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # API Gateway Proxy
  ingress {
    from_port   = 8080
    to_port     = 8080
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
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "s3_kafka_publisher" {
  filename         = "lambda_function.zip"
  function_name    = "s3-kafka-publisher"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 60

  environment {
    variables = {
      KAFKA_BOOTSTRAP_SERVERS = "${aws_instance.kubernetes_master.public_ip}:9092"
      KAFKA_REST_PROXY_URL   = "http://${aws_instance.kubernetes_master.public_ip}:8082"
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

  depends_on = [aws_api_gateway_integration.kafka_integration]
}

resource "aws_api_gateway_stage" "kafka_api_stage" {
  deployment_id = aws_api_gateway_deployment.kafka_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.kafka_api.id
  stage_name    = "prod"
}

# Kubernetes Master Node
resource "aws_instance" "kubernetes_master" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
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
                yum install -y docker python3-pip
                systemctl start docker
                systemctl enable docker
                
                # Install Docker Compose
                curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                chmod +x /usr/local/bin/docker-compose
                
                # Setup Project Directory
                mkdir -p /home/ec2-user/project
                cd /home/ec2-user/project

                # Get Private IP
                PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

                # Create Directories
                mkdir -p logstash/config logstash/pipeline api-gateway-proxy k8s

                # Write docker-compose.yml (including api-proxy)
                cat << 'DOCKER_COMPOSE' > docker-compose.yml
                version: '3.8'

                services:
                  zookeeper:
                    image: confluentinc/cp-zookeeper:latest
                    container_name: zookeeper
                    environment:
                      ZOOKEEPER_CLIENT_PORT: 2181
                      ZOOKEEPER_TICK_TIME: 2000
                    ports:
                      - "2181:2181"
                    networks:
                      - kafka-network

                  kafka:
                    image: confluentinc/cp-kafka:latest
                    container_name: kafka
                    depends_on:
                      - zookeeper
                    ports:
                      - "9092:9092"
                      - "29092:29092"
                    environment:
                      KAFKA_BROKER_ID: 1
                      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
                      # Use the EC2 private IP for the external listener so K8s pods can reach it
                      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://__PRIVATE_IP__:9092
                      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
                      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
                      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
                      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
                    networks:
                      - kafka-network

                  elasticsearch:
                    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
                    container_name: elasticsearch
                    environment:
                      - discovery.type=single-node
                      - xpack.security.enabled=false
                      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
                    ports:
                      - "9200:9200"
                      - "9300:9300"
                    volumes:
                      - elasticsearch-data:/usr/share/elasticsearch/data
                    networks:
                      - elk-network

                  logstash:
                    image: docker.elastic.co/logstash/logstash:8.11.0
                    container_name: logstash
                    depends_on:
                      - elasticsearch
                    ports:
                      - "5000:5000"
                      - "9600:9600"
                    volumes:
                      - ./logstash/pipeline:/usr/share/logstash/pipeline
                      - ./logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml
                    networks:
                      - elk-network
                      - kafka-network

                  kibana:
                    image: docker.elastic.co/kibana/kibana:8.11.0
                    container_name: kibana
                    depends_on:
                      - elasticsearch
                    ports:
                      - "5601:5601"
                    environment:
                      ELASTICSEARCH_HOSTS: http://elasticsearch:9200
                    networks:
                      - elk-network

                  kafka-rest-proxy:
                    image: confluentinc/cp-kafka-rest:latest
                    container_name: kafka-rest-proxy
                    depends_on:
                      - kafka
                    ports:
                      - "8082:8082"
                    environment:
                      KAFKA_REST_HOST_NAME: kafka-rest-proxy
                      KAFKA_REST_BOOTSTRAP_SERVERS: kafka:29092
                      KAFKA_REST_LISTENERS: http://0.0.0.0:8082
                    networks:
                      - kafka-network

                  api-proxy:
                    build:
                      context: ./api-gateway-proxy
                    container_name: api-proxy
                    ports:
                      - "8080:8080"
                    environment:
                      KAFKA_BOOTSTRAP_SERVERS: kafka:29092
                      KAFKA_TOPIC: api-events
                    depends_on:
                      - kafka
                    networks:
                      - kafka-network

                networks:
                  kafka-network:
                    driver: bridge
                  elk-network:
                    driver: bridge

                volumes:
                  elasticsearch-data:
                    driver: local
                DOCKER_COMPOSE

                # Replace placeholder with actual IP
                sed -i "s/__PRIVATE_IP__/$PRIVATE_IP/g" docker-compose.yml

                # Write Logstash Config
                cat << 'LOGSTASH_YML' > logstash/config/logstash.yml
                http.host: "0.0.0.0"
                xpack.monitoring.enabled: false
                LOGSTASH_YML

                cat << 'LOGSTASH_CONF' > logstash/pipeline/logstash.conf
                input {
                  kafka {
                    bootstrap_servers => "kafka:29092"
                    topics => ["orders", "s3-events", "api-events"]
                    codec => "json"
                    group_id => "logstash-consumer-group"
                    consumer_threads => 3
                  }
                }

                filter {
                  if ![timestamp] {
                    mutate {
                      add_field => { "timestamp" => "%%{@timestamp}" }
                    }
                  }
                  if [message] =~ /^\{.*\}$/ {
                    json {
                      source => "message"
                      target => "parsed_message"
                    }
                  }
                }

                output {
                  elasticsearch {
                    hosts => ["elasticsearch:9200"]
                    index => "logstash-%%{+YYYY.MM.dd}"
                  }
                  stdout { codec => rubydebug }
                }
                LOGSTASH_CONF

                # Write API Proxy App
                cat << 'APP_PY' > api-gateway-proxy/app.py
                from flask import Flask, request, jsonify
                from kafka import KafkaProducer
                import json
                import logging
                import os
                import time

                app = Flask(__name__)
                logging.basicConfig(level=logging.INFO)
                logger = logging.getLogger(__name__)

                KAFKA_BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
                KAFKA_TOPIC = os.environ.get('KAFKA_TOPIC', 'api-events')

                # Retry connection to Kafka
                producer = None
                for i in range(10):
                    try:
                        producer = KafkaProducer(
                            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS.split(','),
                            value_serializer=lambda v: json.dumps(v).encode('utf-8')
                        )
                        logger.info("Connected to Kafka")
                        break
                    except Exception as e:
                        logger.warning(f"Failed to connect to Kafka (attempt {i+1}): {e}")
                        time.sleep(5)

                @app.route('/health', methods=['GET'])
                def health():
                    return jsonify({'status': 'healthy'}), 200

                @app.route('/publish', methods=['POST'])
                def publish_event():
                    try:
                        if not producer:
                             return jsonify({'error': 'Kafka producer not initialized'}), 500
                        data = request.get_json()
                        if not data: return jsonify({'error': 'No data provided'}), 400
                        event = {'data': data, 'source': 'api-gateway'}
                        producer.send(KAFKA_TOPIC, value=event)
                        logger.info(f"Published event to Kafka: {event}")
                        return jsonify({'status': 'success'}), 200
                    except Exception as e:
                        logger.error(f"Error publishing: {str(e)}")
                        return jsonify({'error': str(e)}), 500

                if __name__ == '__main__':
                    app.run(host='0.0.0.0', port=8080)
                APP_PY

                cat << 'REQ_TXT' > api-gateway-proxy/requirements.txt
                flask
                kafka-python
                REQ_TXT

                cat << 'DOCKERFILE' > api-gateway-proxy/Dockerfile
                FROM python:3.9-slim
                WORKDIR /app
                COPY requirements.txt .
                RUN pip install --no-cache-dir -r requirements.txt
                COPY app.py .
                CMD ["python", "app.py"]
                DOCKERFILE

                # Start Docker Compose
                /usr/local/bin/docker-compose up -d --build

                # Deploy K8s Consumers
                cat << 'K8S_S3' > k8s/kafka-consumer-s3-events.yaml
                apiVersion: apps/v1
                kind: Deployment
                metadata:
                  name: kafka-consumer-s3
                spec:
                  replicas: 1
                  selector:
                    matchLabels:
                      app: kafka-consumer-s3
                  template:
                    metadata:
                      labels:
                        app: kafka-consumer-s3
                    spec:
                      containers:
                      - name: consumer
                        image: python:3.9-slim
                        command: ["/bin/sh", "-c"]
                        args:
                          - |
                            pip install kafka-python &&
                            python -u -c '
                            from kafka import KafkaConsumer
                            import json
                            import os

                            consumer = KafkaConsumer(
                                "s3-events",
                                bootstrap_servers=["__PRIVATE_IP__:9092"],
                                auto_offset_reset="earliest",
                                value_deserializer=lambda x: json.loads(x.decode("utf-8"))
                            )
                            print("Listening for messages on s3-events...")
                            for message in consumer:
                                print(f"Received: {message.value}")
                            '
                K8S_S3

                # Replace placeholder with actual IP in K8s manifest
                sed -i "s/__PRIVATE_IP__/$PRIVATE_IP/g" k8s/kafka-consumer-s3-events.yaml

                export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
                kubectl apply -f k8s/

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
  key_name                    = aws_key_pair.deployer.key_name
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
