output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.master.public_ip}"
}

output "kibana_url" {
  value = "http://${aws_instance.master.public_ip}:5601"
}

output "api_url" {
  value = "${aws_apigatewayv2_api.api.api_endpoint}/event"
}

output "s3_bucket" {
  value = aws_s3_bucket.b.id
}
