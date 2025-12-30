output "kubernetes_master_public_ip" {
  description = "Public IP of Kubernetes Master"
  value       = aws_instance.kubernetes_master.public_ip
}

output "kubernetes_worker_public_ip" {
  description = "Public IP of Kubernetes Worker"
  value       = aws_instance.kubernetes_worker.public_ip
}

output "api_gateway_url" {
  description = "API Gateway Invoke URL"
  value       = "${aws_api_gateway_deployment.kafka_api_deployment.invoke_url}/events"
}

output "s3_bucket_name" {
  description = "S3 Bucket Name"
  value       = aws_s3_bucket.data_bucket.id
}

output "lambda_function_name" {
  description = "Lambda Function Name"
  value       = aws_lambda_function.s3_kafka_publisher.function_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "kibana_url" {
  description = "Kibana Dashboard URL"
  value       = "http://${aws_instance.kubernetes_master.public_ip}:5601"
}

output "elasticsearch_url" {
  description = "Elasticsearch URL"
  value       = "http://${aws_instance.kubernetes_master.public_ip}:9200"
}
