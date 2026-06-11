terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# provider "aws" {
#   region = "ap-south-1"
# }

# This fetches your AWS account ID automatically
data "aws_caller_identity" "current" {}

# This generates a random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}