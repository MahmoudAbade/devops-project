variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the Public Subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "az" {
  description = "Availability Zone"
  type        = string
  default     = "eu-central-1a"
}

variable "ami_id" {
  description = "AMI ID for the EC2 Instance (Amazon Linux 2023)"
  type        = string
  default     = "ami-015f3aa67b494b27e"
}

variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
  default     = "m5.large"
}
