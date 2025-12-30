#!/bin/bash

# DevOps Final Project - Deployment Script
# This script automates the deployment of Kafka and ELK stack on the Kubernetes master node

set -e

echo "=========================================="
echo "DevOps Final Project - Deployment Script"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root or with sudo"
    exit 1
fi

print_info "Starting deployment..."

# Step 1: Update system
print_info "Updating system packages..."
yum update -y

# Step 2: Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    print_info "Installing Docker..."
    yum install -y docker
    systemctl start docker
    systemctl enable docker
else
    print_info "Docker is already installed"
fi

# Step 3: Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    print_info "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    print_info "Docker Compose is already installed"
fi

# Step 4: Create project directory
PROJECT_DIR="/opt/devops-project"
print_info "Creating project directory at $PROJECT_DIR..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Step 5: Create docker-compose.yml
print_info "Creating Docker Compose configuration..."
cat > docker-compose.yml << 'EOF'
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
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://0.0.0.0:9092
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

networks:
  kafka-network:
    driver: bridge
  elk-network:
    driver: bridge

volumes:
  elasticsearch-data:
    driver: local
EOF

# Step 6: Create Logstash configuration
print_info "Creating Logstash configuration..."
mkdir -p logstash/pipeline logstash/config

cat > logstash/pipeline/logstash.conf << 'EOF'
input {
  kafka {
    bootstrap_servers => "kafka:29092"
    topics => ["orders", "s3-events", "api-events"]
    codec => "json"
    group_id => "logstash-consumer-group"
    consumer_threads => 3
  }
  
  tcp {
    port => 5000
    codec => json_lines
  }
}

filter {
  if ![timestamp] {
    mutate {
      add_field => { "timestamp" => "%{@timestamp}" }
    }
  }
  
  if [message] =~ /^\{.*\}$/ {
    json {
      source => "message"
      target => "parsed_message"
    }
  }
  
  mutate {
    add_field => {
      "environment" => "production"
      "service" => "kafka-consumer"
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "logstash-%{+YYYY.MM.dd}"
  }
  
  stdout {
    codec => rubydebug
  }
}
EOF

cat > logstash/config/logstash.yml << 'EOF'
http.host: "0.0.0.0"
xpack.monitoring.enabled: false
EOF

# Step 7: Start Docker Compose services
print_info "Starting Docker Compose services..."
docker-compose up -d

# Step 8: Wait for services to be ready
print_info "Waiting for services to start (60 seconds)..."
sleep 60

# Step 9: Check service status
print_info "Checking service status..."
docker-compose ps

# Step 10: Verify Elasticsearch
print_info "Verifying Elasticsearch..."
curl -s http://localhost:9200/_cluster/health?pretty || print_warning "Elasticsearch not ready yet"

# Step 11: Create Kafka topics
print_info "Creating Kafka topics..."
docker exec kafka kafka-topics --create --if-not-exists --topic orders --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1
docker exec kafka kafka-topics --create --if-not-exists --topic s3-events --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1
docker exec kafka kafka-topics --create --if-not-exists --topic api-events --bootstrap-server localhost:9092 --partitions 2 --replication-factor 1

# Step 12: List Kafka topics
print_info "Listing Kafka topics..."
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Step 13: Install Python and dependencies for API Gateway Proxy
print_info "Installing Python dependencies..."
yum install -y python3 python3-pip

# Step 14: Create API Gateway Proxy
print_info "Setting up API Gateway Proxy..."
mkdir -p /opt/api-gateway-proxy
cd /opt/api-gateway-proxy

cat > app.py << 'EOF'
from flask import Flask, request, jsonify
from kafka import KafkaProducer
import json
import logging
import os

app = Flask(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

KAFKA_BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
KAFKA_TOPIC = os.environ.get('KAFKA_TOPIC', 'api-events')

producer = KafkaProducer(
    bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS.split(','),
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy'}), 200

@app.route('/publish', methods=['POST'])
def publish_event():
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        event = {
            'data': data,
            'source': 'api-gateway',
            'headers': dict(request.headers)
        }
        
        future = producer.send(KAFKA_TOPIC, value=event)
        result = future.get(timeout=10)
        
        logger.info(f"Published event to Kafka: {event}")
        
        return jsonify({
            'status': 'success',
            'message': 'Event published to Kafka',
            'topic': KAFKA_TOPIC,
            'partition': result.partition,
            'offset': result.offset
        }), 200
        
    except Exception as e:
        logger.error(f"Error publishing event: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/events', methods=['POST'])
def receive_event():
    return publish_event()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

cat > requirements.txt << 'EOF'
Flask==3.0.0
kafka-python==2.0.2
EOF

pip3 install -r requirements.txt

# Step 15: Create systemd service for API Gateway Proxy
print_info "Creating systemd service for API Gateway Proxy..."
cat > /etc/systemd/system/api-gateway-proxy.service << 'EOF'
[Unit]
Description=API Gateway Proxy Service
After=network.target docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/api-gateway-proxy
Environment="KAFKA_BOOTSTRAP_SERVERS=localhost:9092"
Environment="KAFKA_TOPIC=api-events"
ExecStart=/usr/bin/python3 /opt/api-gateway-proxy/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable api-gateway-proxy
systemctl start api-gateway-proxy

# Final status
echo ""
echo "=========================================="
print_info "Deployment completed successfully!"
echo "=========================================="
echo ""
print_info "Service URLs:"
echo "  - Kibana: http://$(hostname -I | awk '{print $1}'):5601"
echo "  - Elasticsearch: http://$(hostname -I | awk '{print $1}'):9200"
echo "  - Kafka: $(hostname -I | awk '{print $1}'):9092"
echo "  - API Gateway Proxy: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
print_info "Next steps:"
echo "  1. Deploy Kubernetes consumers: kubectl apply -f k8s/"
echo "  2. Access Kibana and create index patterns"
echo "  3. Test the API Gateway: curl -X POST http://localhost:8080/publish -H 'Content-Type: application/json' -d '{\"test\": \"data\"}'"
echo ""
