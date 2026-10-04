terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket is passed at init time (-backend-config="bucket=...") so this file has no
  # account-specific values. use_lockfile gives S3-native state locking (no DynamoDB table).
  backend "s3" {
    key          = "poc/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}
