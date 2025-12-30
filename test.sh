#!/bin/bash

# Testing script for the DevOps Final Project

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get master IP
MASTER_IP=${1:-localhost}

echo "=========================================="
echo "DevOps Final Project - Testing Script"
echo "=========================================="
echo "Master IP: $MASTER_IP"
echo ""

# Test 1: Elasticsearch Health
print_test "Testing Elasticsearch health..."
if curl -s "http://$MASTER_IP:9200/_cluster/health?pretty" | grep -q "green\|yellow"; then
    print_success "Elasticsearch is healthy"
else
    print_error "Elasticsearch is not responding"
fi
echo ""

# Test 2: Kibana
print_test "Testing Kibana..."
if curl -s -o /dev/null -w "%{http_code}" "http://$MASTER_IP:5601" | grep -q "200\|302"; then
    print_success "Kibana is accessible"
else
    print_error "Kibana is not accessible"
fi
echo ""

# Test 3: Kafka Topics
print_test "Listing Kafka topics..."
if command -v docker &> /dev/null; then
    docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
    print_success "Kafka topics listed"
else
    print_error "Docker not available, skipping Kafka test"
fi
echo ""

# Test 4: API Gateway Proxy
print_test "Testing API Gateway Proxy..."
response=$(curl -s -X POST "http://$MASTER_IP:8080/publish" \
    -H "Content-Type: application/json" \
    -d '{"test": "data", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}')

if echo "$response" | grep -q "success"; then
    print_success "API Gateway Proxy is working"
    echo "Response: $response"
else
    print_error "API Gateway Proxy test failed"
    echo "Response: $response"
fi
echo ""

# Test 5: Kubernetes Pods
print_test "Checking Kubernetes pods..."
if command -v kubectl &> /dev/null; then
    kubectl get pods
    print_success "Kubernetes pods listed"
else
    print_error "kubectl not available"
fi
echo ""

# Test 6: Send test order event
print_test "Sending test order event..."
order_data='{
  "event_type": "order_created",
  "order_id": "TEST-'$(date +%s)'",
  "customer": "Test Customer",
  "items": [
    {
      "product_id": 1,
      "quantity": 2,
      "price": 29.99
    }
  ],
  "total_amount": 59.98,
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

response=$(curl -s -X POST "http://$MASTER_IP:8080/publish" \
    -H "Content-Type: application/json" \
    -d "$order_data")

if echo "$response" | grep -q "success"; then
    print_success "Order event sent successfully"
    echo "Response: $response"
else
    print_error "Failed to send order event"
fi
echo ""

# Test 7: Check Elasticsearch indices
print_test "Checking Elasticsearch indices..."
curl -s "http://$MASTER_IP:9200/_cat/indices?v"
echo ""

# Test 8: Query recent logs
print_test "Querying recent logs from Elasticsearch..."
curl -s -X GET "http://$MASTER_IP:9200/kafka-*/_search?pretty" \
    -H "Content-Type: application/json" \
    -d '{
      "size": 5,
      "sort": [{"timestamp": {"order": "desc"}}],
      "query": {"match_all": {}}
    }' | head -50
echo ""

echo "=========================================="
echo "Testing completed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Open Kibana: http://$MASTER_IP:5601"
echo "2. Create index pattern: kafka-*"
echo "3. View logs in Discover tab"
echo ""
