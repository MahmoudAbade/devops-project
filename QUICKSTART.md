# Quick Start Guide

## Prerequisites Checklist

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] Terraform installed (v1.0+)
- [ ] SSH key pair created in AWS (note the name)
- [ ] kubectl installed (optional, for Kubernetes management)

## Quick Deployment (5 Steps)

### Step 1: Package Lambda Function (2 minutes)

```powershell
cd "c:\Users\mahmo\Documents\HackerU\Final project"
.\package-lambda.ps1
```

### Step 2: Update Configuration (1 minute)

Edit `variables.tf` and update:
- `s3_bucket_name`: Must be globally unique (e.g., `devops-yourname-bucket-2025`)
- `key_name`: Your AWS SSH key pair name

### Step 3: Deploy Infrastructure (10-15 minutes)

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

**Save the outputs!** You'll need:
- `kubernetes_master_public_ip`
- `api_gateway_url`
- `s3_bucket_name`

### Step 4: Deploy Kafka & ELK Stack (5 minutes)

SSH into the master node:
```bash
ssh -i your-key.pem ec2-user@<kubernetes_master_public_ip>
```

Upload and run the deployment script:
```bash
# Copy deploy.sh to the server, then:
chmod +x deploy.sh
sudo ./deploy.sh
```

### Step 5: Deploy Kubernetes Consumers (2 minutes)

On the master node:
```bash
# Setup kubectl
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

# Deploy consumers
kubectl apply -f k8s/consumer-configmap.yaml
kubectl apply -f k8s/kafka-consumer-orders.yaml
kubectl apply -f k8s/kafka-consumer-s3-events.yaml

# Verify
kubectl get pods
```

## Verification (3 Steps)

### 1. Access Kibana

Open browser: `http://<master-ip>:5601`

- Go to **Stack Management** → **Index Patterns**
- Create pattern: `kafka-*`
- Set time field: `timestamp`

### 2. Test API Gateway

```bash
curl -X POST <api_gateway_url> \
  -H "Content-Type: application/json" \
  -d '{"event": "test", "data": "hello world"}'
```

### 3. Test S3 Upload

```bash
aws s3 cp data/orders.json s3://<bucket-name>/test/orders.json
```

## View Logs in Kibana

1. Open Kibana: `http://<master-ip>:5601`
2. Click **Discover** in the left menu
3. Select `kafka-*` index pattern
4. Filter by topic: `topic: "orders"` or `topic: "s3-events"`
5. View real-time logs!

## Troubleshooting

### Issue: Terraform fails with "bucket name already exists"
**Solution**: Change `s3_bucket_name` in `variables.tf` to a unique value

### Issue: Cannot SSH to EC2 instance
**Solution**: 
- Check security group allows SSH from your IP
- Verify you're using the correct key pair
- Check the instance is in "running" state

### Issue: Kibana shows "No data"
**Solution**:
- Wait 2-3 minutes for data to flow
- Send test events using the test script
- Check Elasticsearch: `curl http://<master-ip>:9200/_cat/indices`

### Issue: Kafka consumers not running
**Solution**:
```bash
kubectl get pods
kubectl logs <pod-name>
kubectl describe pod <pod-name>
```

## Testing Script

Run the automated test script:
```bash
chmod +x test.sh
./test.sh <master-ip>
```

## Architecture Overview

```
Internet
   |
   v
API Gateway -----> API Proxy (Flask) -----> Kafka
                                              |
S3 Bucket -----> Lambda Function ---------> Kafka
                                              |
                                              v
                                         Kafka Topics
                                         (orders, s3-events, api-events)
                                              |
                                              v
                                    +-------------------+
                                    |                   |
                                    v                   v
                            K8s Consumers          Logstash
                                    |                   |
                                    v                   v
                                    Elasticsearch <-----+
                                          |
                                          v
                                       Kibana
                                    (Visualization)
```

## Important URLs

After deployment, you'll have access to:

- **Kibana**: `http://<master-ip>:5601`
- **Elasticsearch**: `http://<master-ip>:9200`
- **API Gateway**: `<api_gateway_url>/events`
- **Kafka**: `<master-ip>:9092`

## Cleanup

To destroy all resources:
```bash
terraform destroy -auto-approve
```

**Warning**: This deletes everything including data!

## Next Steps

1. **Explore Kibana**:
   - Create visualizations
   - Build dashboards
   - Set up alerts

2. **Test Data Flow**:
   - Send various events through API Gateway
   - Upload different files to S3
   - Monitor logs in real-time

3. **Scale Consumers**:
   ```bash
   kubectl scale deployment kafka-consumer-orders --replicas=3
   ```

4. **Monitor Resources**:
   ```bash
   kubectl top pods
   kubectl top nodes
   ```

## Support

- Check `README.md` for detailed documentation
- Review Terraform outputs: `terraform output`
- View service logs: `docker-compose logs -f <service-name>`

## Tips

1. **Save Terraform outputs** immediately after deployment
2. **Create Kibana index patterns** before testing
3. **Use the test script** to verify everything is working
4. **Monitor CloudWatch** for Lambda function logs
5. **Check Docker logs** if services aren't responding

## Time Estimates

- Total deployment time: ~25-30 minutes
- Testing and verification: ~10 minutes
- Kibana setup and exploration: ~15 minutes

**Total**: ~1 hour for complete setup and testing

Good luck with your DevOps Final Project! 🚀
