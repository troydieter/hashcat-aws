terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}


provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      "project"     = "hashcat"
      "environment" = var.environment
      "id"          = random_id.rando.hex
      "cost_center" = "aws_credits"
    }
  }
}
