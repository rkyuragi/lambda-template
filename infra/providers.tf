terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.5" }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

