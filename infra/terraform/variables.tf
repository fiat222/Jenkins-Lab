variable "aws_endpoint" {
  description = "LocalStack edge endpoint reachable from the pipeline network"
  type        = string
  default     = "http://localstack:4566"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ami_id" {
  description = "Ubuntu 16.04 image published by LocalStack's EC2 mock"
  type        = string
  default     = "ami-785db401"
}

variable "allowed_ingress_cidr" {
  description = "Network allowed to reach taskflow-api; never 0.0.0.0/0"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "host_image" {
  description = "Debian image for the Ansible-managed stand-in host"
  type        = string
  default     = "python:3.12-slim-bookworm"
}

variable "docker_network" {
  type    = string
  default = "jenkins-net"
}
