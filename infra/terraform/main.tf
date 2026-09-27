# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, bound by the pipeline.
provider "aws" {
  region                      = var.region
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ec2 = var.aws_endpoint
    iam = var.aws_endpoint
    s3  = var.aws_endpoint
    sts = var.aws_endpoint
  }
}

resource "aws_security_group" "taskflow" {
  name        = "taskflow-api"
  description = "Allow taskflow-api traffic on 8080"

  ingress {
    description = "taskflow-api HTTP from the trusted network only"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  # Ansible installs Node.js/Docker and pulls the image, which needs outbound HTTPS.
  #tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "HTTPS to package mirrors and the container registry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "taskflow" {
  name               = "taskflow-api-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "taskflow" {
  name = "taskflow-api-instance"
  role = aws_iam_role.taskflow.name
}

resource "aws_instance" "taskflow" {
  # LocalStack returns 501 for MonitorInstances, so detailed monitoring cannot be enabled here.
  #checkov:skip=CKV_AWS_126:LocalStack community does not implement EC2 detailed monitoring
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.taskflow.id]
  iam_instance_profile   = aws_iam_instance_profile.taskflow.name
  ebs_optimized          = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "taskflow-api"
  }
}
