variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-central-1"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instance"
  type        = string
  default     = "ami-015f3aa67b494b27e" 
}

variable "instance_type" {
  description = "The type of EC2 instance to use"
  type        = string
  default     = "m7i-flex.large"
}

variable "key_name" {
  description = "The name of the SSH key pair"
  type        = string
  default     = "MyKey.pem"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for data uploads"
  type        = string
  default     = "devops-final-project-data-bucket-unique-mahmnoud"
}