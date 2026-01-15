# DevOps Final Project - Event-Driven Architecture with ELK Monitoring

## Project Overview

This project implements a complete event-driven architecture on AWS with centralized logging and observability using the ELK stack (Elasticsearch, Logstash, Kibana). The system demonstrates real-world DevOps practices including Infrastructure as Code, container orchestration, message streaming, and monitoring.

## Architecture

The architecture consists of the following components:

### Core Infrastructure
- **VPC**: Custom VPC with public subnet for resource isolation
- **EC2 Instances**: 
  - Kubernetes Master Node (K3s)
  - Kubernetes Worker Node (K3s)
- **API Gateway**: RESTful API endpoint for external event ingestion
- **S3 Bucket**: Data storage with event triggers
- **Lambda Function**: Serverless function triggered by S3 uploads

### Messaging & Processing
- **Apache Kafka**: Message broker for event streaming
- **Zookeeper**: Kafka cluster coordination
- **Kafka Consumers**: Kubernetes-deployed consumers processing events

### Monitoring & Observability
- **Elasticsearch**: Log storage and indexing
- **Logstash**: Log processing and enrichment pipeline
- **Kibana**: Visualization and dashboard interface

## Technology Stack

- **Infrastructure**: Terraform, AWS (EC2, VPC, IAM, API Gateway, S3, Lambda)
- **Container Orchestration**: Kubernetes (K3s)
- **Message Streaming**: Apache Kafka, Zookeeper
- **Monitoring**: ELK Stack (Elasticsearch, Logstash, Kibana)
- **Languages**: Python, HCL (Terraform)
- **Container Runtime**: Docker, Docker Compose

## Project Structure

```
.
├── main.tf                          # Main Terraform configuration
├── variables.tf                     # Terraform variables
├── output.tf                        # Terraform outputs
├── docker-compose.yml               # Docker Compose for Kafka & ELK
├── lambda_function.py               # Lambda function code
├── api-gateway-proxy/
│   ├── app.py                       # Flask app for API Gateway integration
│   └── requirements.txt             # Python dependencies
├── k8s/
│   ├── kafka-consumer-orders.yaml   # Kafka consumer deployment for orders
│   ├── kafka-consumer-s3-events.yaml # Kafka consumer for S3 events
│   ├── consumer-configmap.yaml      # ConfigMap with consumer code
│   └── consumer.py                  # Kafka consumer Python application
├── logstash/
│   ├── pipeline/
│   │   └── logstash.conf           # Logstash pipeline configuration
│   └── config/
│       └── logstash.yml            # Logstash settings
└── data/
    ├── generate-data.py             # Data generation script
    ├── orders.json                  # Sample orders data
    ├── products.json                # Sample products data
    └── suppliers.json               # Sample suppliers data
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** (v1.0+)
4. **SSH Key Pair** in AWS (default: `AWS-eu-central-1`)
5. **kubectl** for Kubernetes management
6. **Docker** and **Docker Compose** (for local testing)

## Deployment Instructions

### Step 1: Prepare Lambda Function

Create the Lambda deployment package:

```bash
cd "c:\Users\mahmo\Documents\HackerU\Final project"
powershell Compress-Archive -Path lambda_function.py -DestinationPath lambda_function.zip
```

### Step 2: Configure Variables

Update `variables.tf` with your specific values:

```hcl
variable "s3_bucket_name" {
  default = "your-unique-bucket-name-here"
}

variable "key_name" {
  default = "your-ssh-key-name"
}
```

### Step 3: Deploy Infrastructure with Terraform

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

**Note**: Save the output values - you'll need them for configuration.

### Step 4: Access Kubernetes Master

SSH into the Kubernetes master node:

```bash
ssh -i your-key.pem ec2-user@<kubernetes_master_public_ip>
```

### Step 5: Deploy Kafka and ELK Stack

On the master node, create the Docker Compose file and start services:

```bash
# Copy docker-compose.yml to the master node
# Then run:
sudo docker-compose up -d

# Verify services are running
sudo docker-compose ps
```

### Step 6: Deploy Kafka Consumers to Kubernetes

```bash
# Copy kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# Deploy ConfigMap
kubectl apply -f k8s/consumer-configmap.yaml

# Deploy consumers
kubectl apply -f k8s/kafka-consumer-orders.yaml
kubectl apply -f k8s/kafka-consumer-s3-events.yaml

# Verify deployments
kubectl get pods
kubectl get services
```

### Step 7: Deploy API Gateway Proxy

```bash
# On the master node
cd /home/ec2-user
mkdir api-gateway-proxy
cd api-gateway-proxy

# Copy app.py and requirements.txt
# Install dependencies
pip3 install -r requirements.txt

# Run the application
nohup python3 app.py &
```

### Step 8: Configure Kibana

1. Access Kibana at `http://<kubernetes_master_public_ip>:5601`
2. Navigate to **Stack Management** → **Index Patterns**
3. Create index patterns:
   - `kafka-*` for Kafka consumer logs
   - `logstash-*` for Logstash processed logs
4. Go to **Discover** to view logs
5. Create visualizations and dashboards

## Testing the System

### Test 1: API Gateway Event Publishing

```bash
curl -X POST https://<api-gateway-url>/events \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "order_created",
    "order_id": "12345",
    "customer": "John Doe",
    "amount": 99.99
  }'
```

### Test 2: S3 Upload Trigger

```bash
aws s3 cp data/orders.json s3://<bucket-name>/orders.json
```

This will trigger the Lambda function, which publishes an event to Kafka.

### Test 3: Verify Logs in Kibana

1. Open Kibana: `http://<master-ip>:5601`
2. Go to **Discover**
3. Select the `kafka-*` index pattern
4. Filter by topic: `topic: "orders"` or `topic: "s3-events"`
5. View the processed messages

## Monitoring and Observability

### Elasticsearch

- **URL**: `http://<master-ip>:9200`
- **Health Check**: `curl http://<master-ip>:9200/_cluster/health`
- **Indices**: `curl http://<master-ip>:9200/_cat/indices`

### Kibana

- **URL**: `http://<master-ip>:5601`
- **Features**:
  - Log searching and filtering
  - Real-time dashboards
  - Metric visualization
  - Alerting (optional)

### Kafka

- **Bootstrap Server**: `<master-ip>:9092`
- **Topics**:
  - `orders` - Order events from API Gateway
  - `s3-events` - S3 upload events from Lambda
  - `api-events` - General API events

## Data Flow

1. **API Gateway → Kafka**:
   - External requests → API Gateway → API Proxy (Flask) → Kafka topic

2. **S3 → Lambda → Kafka**:
   - File upload → S3 bucket → Lambda trigger → Kafka topic

3. **Kafka → Consumers → Elasticsearch**:
   - Kafka topics → Consumer pods → Process & log → Elasticsearch

4. **Elasticsearch → Kibana**:
   - Indexed logs → Kibana queries → Visualizations & dashboards

## Kafka Topics

| Topic | Description | Producers | Consumers |
|-------|-------------|-----------|-----------|
| `orders` | Order events | API Gateway Proxy | kafka-consumer-orders |
| `s3-events` | S3 upload events | Lambda Function | kafka-consumer-s3-events |
| `api-events` | General API events | API Gateway Proxy | Logstash |

## Kubernetes Resources

### Deployments

- `kafka-consumer-orders`: 2 replicas processing order events
- `kafka-consumer-s3-events`: 1 replica processing S3 events

### Services

- `kafka-consumer-orders-service`: ClusterIP on port 8080
- `kafka-consumer-s3-events-service`: ClusterIP on port 8080

## Troubleshooting

### Kafka Connection Issues

```bash
# Check Kafka container
sudo docker ps | grep kafka

# View Kafka logs
sudo docker logs kafka

# Test Kafka connectivity
telnet <master-ip> 9092
```

### Kubernetes Pod Issues

```bash
# Check pod status
kubectl get pods

# View pod logs
kubectl logs <pod-name>

# Describe pod for events
kubectl describe pod <pod-name>

# Execute into pod
kubectl exec -it <pod-name> -- /bin/bash
```

### Elasticsearch Issues

```bash
# Check Elasticsearch health
curl http://<master-ip>:9200/_cluster/health?pretty

# View indices
curl http://<master-ip>:9200/_cat/indices?v

# Check Elasticsearch logs
sudo docker logs elasticsearch
```

### Lambda Function Issues

```bash
# View Lambda logs in CloudWatch
aws logs tail /aws/lambda/s3-kafka-publisher --follow

# Test Lambda function
aws lambda invoke --function-name s3-kafka-publisher \
  --payload '{"test": "data"}' output.json
```

## Security Considerations

### Current Implementation (Development)

- Security groups allow public access for testing
- No authentication on Kafka, Elasticsearch, or Kibana
- Lambda function has basic IAM permissions

### Production Recommendations

1. **Network Security**:
   - Restrict security group rules to specific IP ranges
   - Use private subnets for internal services
   - Implement VPN or bastion host for access

2. **Authentication & Authorization**:
   - Enable Kafka SASL/SSL authentication
   - Configure Elasticsearch security features
   - Implement API Gateway authentication (API keys, Cognito)
   - Use IAM roles with least privilege

3. **Data Encryption**:
   - Enable encryption at rest for S3, EBS volumes
   - Use TLS/SSL for all network communication
   - Encrypt Kafka topics

4. **Monitoring & Auditing**:
   - Enable CloudTrail for AWS API auditing
   - Configure CloudWatch alarms
   - Implement log retention policies

## Cost Optimization

- **EC2 Instances**: Consider using Spot Instances for non-production
- **S3**: Implement lifecycle policies for old data
- **Lambda**: Optimize function memory and timeout
- **Elasticsearch**: Use appropriate instance sizing

## Cleanup

To destroy all resources:

```bash
# Delete Kubernetes resources
kubectl delete -f k8s/

# Stop Docker Compose services
sudo docker-compose down -v

# Destroy Terraform infrastructure
terraform destroy
```

**Warning**: This will delete all resources including data in S3 and Elasticsearch.

## Architecture Decisions

### Why K3s?

- Lightweight Kubernetes distribution
- Easy to install and manage
- Suitable for edge and development environments
- Lower resource requirements

### Why Docker Compose for Kafka & ELK?

- Simplified deployment and management
- Easy to configure and scale
- Good for development and small-scale production
- Can be migrated to Kubernetes operators later

### Why Separate Consumers?

- Topic-specific processing logic
- Independent scaling
- Fault isolation
- Clear separation of concerns

## Future Enhancements

1. **High Availability**:
   - Multi-node Kafka cluster
   - Elasticsearch cluster with replicas
   - Multi-AZ deployment

2. **CI/CD Pipeline**:
   - Automated testing
   - GitOps workflow
   - Container registry integration

3. **Advanced Monitoring**:
   - Prometheus for metrics
   - Grafana for visualization
   - Distributed tracing with Jaeger

4. **Data Processing**:
   - Kafka Streams for real-time processing
   - Apache Flink for complex event processing
   - Data lake integration

## Final Submittion Result
    <img width="1808" height="634" alt="Screenshot (6)" src="https://github.com/user-attachments/assets/10485389-d9de-408f-8017-3b8e6b55272f" />

## References

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [K3s Documentation](https://docs.k3s.io/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Elastic Stack Documentation](https://www.elastic.co/guide/index.html)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)

## License

This project is for educational purposes as part of the DevOps course final project from HackerU college.

## Author

Mahmoud Abade - DevOps Course Final Project - HackerU 2025

## Support

For issues and questions, please refer to the course materials or contact the instructor.
