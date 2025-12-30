# Deployment Checklist

Use this checklist to ensure a smooth deployment of the DevOps Final Project.

## Pre-Deployment Checklist

### AWS Prerequisites
- [ ] AWS Account created and accessible
- [ ] AWS CLI installed on local machine
- [ ] AWS CLI configured with credentials (`aws configure`)
- [ ] Verify AWS credentials: `aws sts get-caller-identity`
- [ ] SSH key pair created in AWS EC2 console
- [ ] Note the SSH key pair name (default: `AWS-eu-central-1`)
- [ ] Download the private key (.pem file) to your local machine

### Local Prerequisites
- [ ] Terraform installed (v1.0 or higher)
- [ ] Verify Terraform: `terraform --version`
- [ ] Git installed (for version control)
- [ ] Text editor or IDE ready (VS Code, etc.)
- [ ] PowerShell available (for Lambda packaging on Windows)

### Project Setup
- [ ] Clone or download the project files
- [ ] Navigate to project directory
- [ ] Review all documentation files (README.md, QUICKSTART.md)
- [ ] Understand the architecture (ARCHITECTURE.md)

## Configuration Checklist

### Step 1: Update Variables
- [ ] Open `variables.tf`
- [ ] Update `s3_bucket_name` to a globally unique value
  - Example: `devops-yourname-bucket-2025`
- [ ] Update `key_name` to match your AWS SSH key pair name
- [ ] Verify `region` matches your desired AWS region
- [ ] Verify `ami_id` is valid for your region
- [ ] Save the file

### Step 2: Package Lambda Function
- [ ] Run `.\package-lambda.ps1` (Windows) or create zip manually
- [ ] Verify `lambda_function.zip` is created
- [ ] Check file size is reasonable (should be < 1MB)

### Step 3: Review Terraform Configuration
- [ ] Review `main.tf` for any custom requirements
- [ ] Check security group rules in `main.tf`
- [ ] Verify instance types match your budget
- [ ] Review IAM policies for Lambda

## Deployment Checklist

### Phase 1: Terraform Deployment (15-20 minutes)

- [ ] Initialize Terraform: `terraform init`
  - [ ] Verify initialization successful
  - [ ] Check `.terraform` directory created

- [ ] Plan deployment: `terraform plan`
  - [ ] Review planned resources
  - [ ] Verify no errors
  - [ ] Check estimated costs

- [ ] Apply configuration: `terraform apply`
  - [ ] Type `yes` when prompted
  - [ ] Wait for completion (10-15 minutes)
  - [ ] Note any errors

- [ ] Save outputs:
  - [ ] Copy `kubernetes_master_public_ip`
  - [ ] Copy `kubernetes_worker_public_ip`
  - [ ] Copy `api_gateway_url`
  - [ ] Copy `s3_bucket_name`
  - [ ] Copy `kibana_url`
  - [ ] Copy `elasticsearch_url`

### Phase 2: Verify AWS Resources (5 minutes)

- [ ] Login to AWS Console
- [ ] Verify VPC created
- [ ] Verify EC2 instances running (Master + Worker)
- [ ] Verify Security Group created
- [ ] Verify S3 bucket created
- [ ] Verify Lambda function created
- [ ] Verify API Gateway created
- [ ] Verify IAM roles created

### Phase 3: Deploy Kafka & ELK Stack (10 minutes)

- [ ] SSH to master node:
  ```bash
  ssh -i your-key.pem ec2-user@<master-ip>
  ```
- [ ] Copy `deploy.sh` to master node
- [ ] Make script executable: `chmod +x deploy.sh`
- [ ] Run deployment: `sudo ./deploy.sh`
- [ ] Wait for completion (5-10 minutes)
- [ ] Verify no errors in output

- [ ] Verify Docker containers running:
  ```bash
  sudo docker ps
  ```
  - [ ] zookeeper running
  - [ ] kafka running
  - [ ] elasticsearch running
  - [ ] logstash running
  - [ ] kibana running
  - [ ] kafka-rest-proxy running

- [ ] Verify Kafka topics created:
  ```bash
  sudo docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
  ```
  - [ ] orders topic exists
  - [ ] s3-events topic exists
  - [ ] api-events topic exists

### Phase 4: Deploy Kubernetes Consumers (5 minutes)

- [ ] Setup kubectl on master node:
  ```bash
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown $USER:$USER ~/.kube/config
  ```

- [ ] Copy Kubernetes manifests to master node
  - [ ] `k8s/consumer-configmap.yaml`
  - [ ] `k8s/kafka-consumer-orders.yaml`
  - [ ] `k8s/kafka-consumer-s3-events.yaml`

- [ ] Deploy ConfigMap:
  ```bash
  kubectl apply -f k8s/consumer-configmap.yaml
  ```
  - [ ] Verify: `kubectl get configmap`

- [ ] Deploy consumers:
  ```bash
  kubectl apply -f k8s/kafka-consumer-orders.yaml
  kubectl apply -f k8s/kafka-consumer-s3-events.yaml
  ```

- [ ] Verify deployments:
  ```bash
  kubectl get deployments
  kubectl get pods
  kubectl get services
  ```
  - [ ] kafka-consumer-orders deployment exists (2 replicas)
  - [ ] kafka-consumer-s3-events deployment exists (1 replica)
  - [ ] All pods in Running state

### Phase 5: Configure Kibana (5 minutes)

- [ ] Open Kibana in browser: `http://<master-ip>:5601`
- [ ] Wait for Kibana to load (may take 1-2 minutes)
- [ ] Navigate to **Stack Management** (gear icon)
- [ ] Click **Index Patterns**
- [ ] Create index pattern:
  - [ ] Click **Create index pattern**
  - [ ] Enter pattern: `kafka-*`
  - [ ] Click **Next step**
  - [ ] Select time field: `timestamp`
  - [ ] Click **Create index pattern**
- [ ] Navigate to **Discover** tab
- [ ] Verify you can see the index pattern

## Testing Checklist

### Test 1: Elasticsearch Health
- [ ] Run: `curl http://<master-ip>:9200/_cluster/health?pretty`
- [ ] Verify status is "green" or "yellow"
- [ ] Verify number_of_nodes > 0

### Test 2: Kibana Access
- [ ] Open browser: `http://<master-ip>:5601`
- [ ] Verify Kibana loads successfully
- [ ] Verify no error messages

### Test 3: API Gateway Event
- [ ] Run test command:
  ```bash
  curl -X POST <api-gateway-url>/events \
    -H "Content-Type: application/json" \
    -d '{"event": "test", "timestamp": "2025-01-01T00:00:00Z"}'
  ```
- [ ] Verify response contains "success"
- [ ] Check Kibana Discover for new log entry

### Test 4: S3 Upload Trigger
- [ ] Upload test file to S3:
  ```bash
  aws s3 cp data/orders.json s3://<bucket-name>/test/orders.json
  ```
- [ ] Verify upload successful
- [ ] Check Lambda logs in CloudWatch
- [ ] Check Kibana for S3 event log

### Test 5: Kafka Consumer Logs
- [ ] View consumer pod logs:
  ```bash
  kubectl logs -f deployment/kafka-consumer-orders
  ```
- [ ] Verify logs show consumer activity
- [ ] Verify no error messages

### Test 6: End-to-End Flow
- [ ] Send event via API Gateway
- [ ] Verify event appears in Kafka topic
- [ ] Verify consumer processes event
- [ ] Verify log appears in Elasticsearch
- [ ] Verify log visible in Kibana

### Test 7: Automated Testing
- [ ] Copy `test.sh` to master node
- [ ] Run: `chmod +x test.sh`
- [ ] Run: `./test.sh localhost`
- [ ] Verify all tests pass

## Post-Deployment Checklist

### Documentation
- [ ] Take screenshots of AWS Console showing resources
- [ ] Take screenshots of Kibana showing logs
- [ ] Document any issues encountered
- [ ] Document any deviations from plan
- [ ] Update README.md with actual values (IPs, URLs)

### Monitoring Setup
- [ ] Create Kibana dashboards for key metrics
- [ ] Set up saved searches in Kibana
- [ ] Test log filtering and searching
- [ ] Verify real-time log updates

### Security Review
- [ ] Review security group rules
- [ ] Verify IAM policies are appropriate
- [ ] Check for any exposed credentials
- [ ] Review CloudWatch logs for errors

### Performance Verification
- [ ] Check EC2 instance CPU/memory usage
- [ ] Check Elasticsearch cluster health
- [ ] Verify Kafka consumer lag is minimal
- [ ] Test system under load (optional)

## Troubleshooting Checklist

### If Terraform Apply Fails
- [ ] Check AWS credentials are valid
- [ ] Verify S3 bucket name is unique
- [ ] Check AWS service limits
- [ ] Review Terraform error messages
- [ ] Check AWS region availability

### If EC2 Instances Don't Start
- [ ] Check AWS Console for instance state
- [ ] Review user-data logs: `/var/log/user-data.log`
- [ ] Verify AMI ID is valid for region
- [ ] Check instance type availability

### If Kafka/ELK Don't Start
- [ ] Check Docker is running: `sudo systemctl status docker`
- [ ] Review Docker Compose logs: `sudo docker-compose logs`
- [ ] Check available disk space: `df -h`
- [ ] Check available memory: `free -h`

### If Kubernetes Pods Fail
- [ ] Check pod status: `kubectl get pods`
- [ ] View pod logs: `kubectl logs <pod-name>`
- [ ] Describe pod: `kubectl describe pod <pod-name>`
- [ ] Check node resources: `kubectl top nodes`

### If Kibana Shows No Data
- [ ] Wait 2-3 minutes for data to flow
- [ ] Send test events
- [ ] Check Elasticsearch indices: `curl http://<master-ip>:9200/_cat/indices`
- [ ] Verify index pattern matches indices
- [ ] Check time range in Kibana

## Cleanup Checklist

### When Ready to Destroy Resources
- [ ] Export any important data from Elasticsearch
- [ ] Save Kibana dashboards/visualizations
- [ ] Backup any important logs
- [ ] Take final screenshots for documentation

### Terraform Destroy
- [ ] Run: `terraform destroy`
- [ ] Type `yes` when prompted
- [ ] Wait for completion (5-10 minutes)
- [ ] Verify all resources deleted in AWS Console

### Manual Cleanup (if needed)
- [ ] Check for any remaining EC2 instances
- [ ] Check for any remaining S3 buckets
- [ ] Check for any remaining Lambda functions
- [ ] Check for any remaining API Gateways
- [ ] Check for any remaining CloudWatch log groups

## Submission Checklist

### Required Deliverables
- [ ] Terraform configuration files (main.tf, variables.tf, output.tf)
- [ ] Screenshots from AWS Console
  - [ ] VPC and subnets
  - [ ] EC2 instances
  - [ ] Security groups
  - [ ] S3 bucket
  - [ ] Lambda function
  - [ ] API Gateway
- [ ] Screenshots from Kibana
  - [ ] Index patterns
  - [ ] Log entries
  - [ ] Dashboards
  - [ ] Search/filter examples
- [ ] README.md file
- [ ] All supporting files (Docker Compose, K8s manifests, etc.)

### Documentation Quality
- [ ] Architecture clearly described
- [ ] Deployment steps documented
- [ ] Assumptions listed
- [ ] Design decisions justified
- [ ] Troubleshooting guide included
- [ ] All manual steps documented

### Final Review
- [ ] All code is properly formatted
- [ ] No sensitive information in files (passwords, keys)
- [ ] All files are properly organized
- [ ] README is clear and comprehensive
- [ ] Screenshots are clear and labeled

### Create Submission Archive
- [ ] Create ZIP file with all project files
- [ ] Include all Terraform files
- [ ] Include all Kubernetes manifests
- [ ] Include all documentation
- [ ] Include all screenshots
- [ ] Verify ZIP file is complete
- [ ] Test extracting ZIP file

## Success Criteria

✅ All infrastructure deployed via Terraform  
✅ Kubernetes cluster running with consumers  
✅ Kafka receiving messages from API Gateway and Lambda  
✅ S3 uploads trigger Lambda function  
✅ Logs flowing to Elasticsearch  
✅ Kibana showing logs with filtering capability  
✅ Complete documentation provided  
✅ Screenshots demonstrate working system  

---

**Estimated Total Time**: 45-60 minutes for full deployment and testing

**Good luck with your DevOps Final Project!** 🚀
