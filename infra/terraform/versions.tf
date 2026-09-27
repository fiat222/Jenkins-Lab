terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }

  # Remote state lives in a LocalStack S3 bucket; never commit terraform.tfstate.
  backend "s3" {
    bucket                      = "taskflow-tfstate"
    key                         = "lab08/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://localstack:4566" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
