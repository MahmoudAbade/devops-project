# Architecture Documentation

## System Architecture Overview

This document describes the architecture of the DevOps Final Project, an event-driven system with centralized logging and monitoring.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                               │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │                         VPC (10.0.0.0/16)                   │   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐  │   │
│  │  │           Public Subnet (10.0.1.0/24)                │  │   │
│  │  │                                                        │  │   │
│  │  │  ┌─────────────────┐      ┌─────────────────┐       │  │   │
│  │  │  │  EC2 Instance   │      │  EC2 Instance   │       │  │   │
│  │  │  │  K8s Master     │      │  K8s Worker     │       │  │   │
│  │  │  │                 │      │                 │       │  │   │
│  │  │  │  - K3s Server   │      │  - K3s Agent    │       │  │   │
│  │  │  │  - Kafka        │      │  - Consumers    │       │  │   │
│  │  │  │  - Zookeeper    │      │                 │       │  │   │
│  │  │  │  - Elasticsearch│      │                 │       │  │   │
│  │  │  │  - Logstash     │      │                 │       │  │   │
│  │  │  │  - Kibana       │      │                 │       │  │   │
│  │  │  │  - API Proxy    │      │                 │       │  │   │
│  │  │  └─────────────────┘      └─────────────────┘       │  │   │
│  │  │                                                        │  │   │
│  │  └──────────────────────────────────────────────────────┘  │   │
│  │                                                              │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐          │
│  │ API Gateway  │   │  S3 Bucket   │   │   Lambda     │          │
│  │              │   │              │   │  Function    │          │
│  │  /events     │   │  Data Store  │   │              │          │
│  └──────────────┘   └──────────────┘   └──────────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Infrastructure Layer (Terraform)

**Components:**
- VPC with public subnet
- Internet Gateway
- Security Groups
- EC2 Instances (Master & Worker)
- API Gateway
- S3 Bucket
- Lambda Function
- IAM Roles and Policies

**Purpose:** Provides the foundational cloud infrastructure

### 2. Container Orchestration Layer (Kubernetes/K3s)

**Components:**
- K3s Master Node (Control Plane)
- K3s Worker Node (Compute)
- Kubernetes Deployments
- Kubernetes Services
- ConfigMaps

**Purpose:** Orchestrates containerized workloads (Kafka consumers)

### 3. Message Streaming Layer (Kafka)

**Components:**
- Apache Kafka Broker
- Zookeeper
- Kafka Topics:
  - `orders`: Order events from API Gateway
  - `s3-events`: S3 upload events from Lambda
  - `api-events`: General API events
- Kafka REST Proxy

**Purpose:** Provides reliable, scalable message streaming

### 4. Application Layer

**Components:**
- **API Gateway Proxy** (Flask):
  - Receives HTTP requests from API Gateway
  - Publishes events to Kafka topics
  - Runs on port 8080

- **Kafka Consumers** (Python):
  - Consume messages from Kafka topics
  - Process and log events
  - Send logs to Elasticsearch
  - Deployed as Kubernetes pods

- **Lambda Function** (Python):
  - Triggered by S3 uploads
  - Publishes S3 events to Kafka

**Purpose:** Processes events and generates logs

### 5. Monitoring & Observability Layer (ELK Stack)

**Components:**
- **Elasticsearch**:
  - Stores and indexes logs
  - Provides search capabilities
  - Port 9200

- **Logstash**:
  - Ingests logs from Kafka and TCP
  - Filters and enriches data
  - Forwards to Elasticsearch
  - Port 5000

- **Kibana**:
  - Visualizes logs and metrics
  - Provides dashboards
  - Port 5601

**Purpose:** Centralized logging, monitoring, and visualization

## Data Flow Diagrams

### Flow 1: API Gateway → Kafka → Elasticsearch

```
External Client
      |
      | HTTP POST
      v
API Gateway (/events)
      |
      | HTTP POST
      v
API Proxy (Flask)
      |
      | Kafka Producer
      v
Kafka Topic (api-events)
      |
      | Kafka Consumer
      v
Kubernetes Consumer Pod
      |
      | Elasticsearch Client
      v
Elasticsearch Index
      |
      | Query
      v
Kibana Dashboard
```

### Flow 2: S3 Upload → Lambda → Kafka → Elasticsearch

```
User/Application
      |
      | Upload File
      v
S3 Bucket
      |
      | S3 Event Trigger
      v
Lambda Function
      |
      | Kafka Producer
      v
Kafka Topic (s3-events)
      |
      | Kafka Consumer
      v
Kubernetes Consumer Pod
      |
      | Elasticsearch Client
      v
Elasticsearch Index
      |
      | Query
      v
Kibana Dashboard
```

### Flow 3: Logstash Pipeline

```
Kafka Topics
      |
      | Kafka Consumer
      v
Logstash Input
      |
      | Filter & Enrich
      v
Logstash Filter
      |
      | Index
      v
Elasticsearch
      |
      | Visualize
      v
Kibana
```

## Network Architecture

### Security Groups

**Main Security Group:**
- Inbound:
  - SSH (22) from anywhere
  - Kubernetes API (6443) from anywhere
  - Kafka (9092) from anywhere
  - Elasticsearch (9200) from anywhere
  - Kibana (5601) from anywhere
  - API Proxy (8080) from anywhere
  - All traffic from same security group
- Outbound:
  - All traffic to anywhere

### Network Flow

```
Internet
   |
   v
Internet Gateway
   |
   v
Public Subnet (10.0.1.0/24)
   |
   +----> EC2 Master (10.0.1.x)
   |
   +----> EC2 Worker (10.0.1.y)
```

## Deployment Architecture

### Kubernetes Deployments

**kafka-consumer-orders:**
- Replicas: 2
- Image: python:3.11-slim
- Environment:
  - KAFKA_BOOTSTRAP_SERVERS: kafka:29092
  - KAFKA_TOPIC: orders
  - CONSUMER_GROUP: orders-consumer-group
  - ELASTICSEARCH_HOST: elasticsearch:9200

**kafka-consumer-s3-events:**
- Replicas: 1
- Image: python:3.11-slim
- Environment:
  - KAFKA_BOOTSTRAP_SERVERS: kafka:29092
  - KAFKA_TOPIC: s3-events
  - CONSUMER_GROUP: s3-events-consumer-group
  - ELASTICSEARCH_HOST: elasticsearch:9200

### Docker Compose Services

**Kafka Stack:**
- zookeeper:2181
- kafka:9092, 29092
- kafka-rest-proxy:8082

**ELK Stack:**
- elasticsearch:9200, 9300
- logstash:5000, 9600
- kibana:5601

## Scalability Considerations

### Horizontal Scaling

1. **Kafka Consumers**: Scale by increasing replicas
   ```bash
   kubectl scale deployment kafka-consumer-orders --replicas=5
   ```

2. **Kafka Brokers**: Add more Kafka containers with different broker IDs

3. **Elasticsearch**: Configure cluster with multiple nodes

4. **EC2 Instances**: Add more worker nodes to K8s cluster

### Vertical Scaling

1. **EC2 Instance Types**: Upgrade to larger instance types
2. **Kafka Memory**: Increase heap size in environment variables
3. **Elasticsearch Memory**: Adjust ES_JAVA_OPTS

## High Availability Design

### Current Implementation (Single Node)
- Single Kafka broker
- Single Elasticsearch node
- Single master, single worker K8s setup

### Production Recommendations

1. **Kafka**:
   - 3+ broker cluster
   - Replication factor: 3
   - Min in-sync replicas: 2

2. **Elasticsearch**:
   - 3+ node cluster
   - Index replicas: 1-2
   - Dedicated master nodes

3. **Kubernetes**:
   - 3+ master nodes
   - Multiple worker nodes across AZs
   - Pod anti-affinity rules

4. **Load Balancing**:
   - Application Load Balancer for API Gateway
   - Network Load Balancer for Kafka

## Monitoring & Alerting

### Metrics to Monitor

1. **Kafka**:
   - Consumer lag
   - Throughput (messages/sec)
   - Broker health

2. **Elasticsearch**:
   - Cluster health
   - Index size
   - Query performance

3. **Kubernetes**:
   - Pod status
   - Resource usage (CPU, Memory)
   - Node health

4. **Application**:
   - Event processing rate
   - Error rates
   - Latency

### Log Indices

- `kafka-orders-YYYY.MM.DD`: Order events
- `kafka-s3-events-YYYY.MM.DD`: S3 events
- `logstash-YYYY.MM.DD`: Logstash processed logs

## Security Architecture

### Current Implementation (Development)

- Open security groups for testing
- No authentication on services
- Basic IAM roles

### Production Security Recommendations

1. **Network Security**:
   - Private subnets for internal services
   - NAT Gateway for outbound traffic
   - Bastion host for SSH access
   - Restrict security groups to specific IPs

2. **Authentication & Authorization**:
   - Kafka SASL/SCRAM authentication
   - Elasticsearch X-Pack security
   - API Gateway API keys or Cognito
   - IAM roles with least privilege

3. **Encryption**:
   - TLS for all network traffic
   - Encryption at rest for S3, EBS
   - Kafka SSL/TLS
   - Elasticsearch TLS

4. **Secrets Management**:
   - AWS Secrets Manager for credentials
   - Kubernetes Secrets for sensitive data
   - Encrypted environment variables

## Disaster Recovery

### Backup Strategy

1. **Elasticsearch**: Snapshot to S3
2. **Kafka**: Replicate to another cluster
3. **S3**: Enable versioning and cross-region replication
4. **Terraform State**: Remote backend with versioning

### Recovery Procedures

1. **Infrastructure**: `terraform apply` from state
2. **Elasticsearch**: Restore from snapshot
3. **Kafka**: Replay from replicated cluster
4. **Applications**: Redeploy from Git repository

## Cost Optimization

### Current Costs (Estimated Monthly)

- EC2 Instances (2x m7i-flex.large): ~$150
- API Gateway: Pay per request
- Lambda: Pay per execution
- S3: Pay per GB stored
- Data Transfer: Pay per GB

### Optimization Strategies

1. Use Spot Instances for non-critical workloads
2. Implement S3 lifecycle policies
3. Right-size EC2 instances based on metrics
4. Use Reserved Instances for stable workloads
5. Enable CloudWatch cost anomaly detection

## Technology Choices & Justification

### Why K3s?
- Lightweight, easy to deploy
- Full Kubernetes compatibility
- Lower resource requirements
- Ideal for edge and development

### Why Kafka?
- High throughput message streaming
- Durable, fault-tolerant
- Scalable architecture
- Industry standard for event streaming

### Why ELK Stack?
- Powerful log aggregation
- Rich visualization capabilities
- Scalable search engine
- Large community and ecosystem

### Why Docker Compose for Kafka/ELK?
- Simplified deployment
- Easy configuration management
- Quick setup for development
- Can migrate to K8s operators later

## Future Enhancements

1. **Service Mesh**: Implement Istio for advanced traffic management
2. **GitOps**: Use ArgoCD for declarative deployments
3. **Observability**: Add Prometheus and Grafana for metrics
4. **Tracing**: Implement Jaeger for distributed tracing
5. **CI/CD**: Jenkins or GitHub Actions pipeline
6. **Auto-scaling**: HPA for Kubernetes, ASG for EC2
7. **Multi-region**: Deploy across multiple AWS regions

## Conclusion

This architecture provides a robust, scalable foundation for event-driven applications with comprehensive monitoring and observability. The modular design allows for easy scaling and enhancement as requirements evolve.
