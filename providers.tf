terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "personal"

  default_tags {
    tags = {
      Project     = "fortigate-vpn-demo"
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}
