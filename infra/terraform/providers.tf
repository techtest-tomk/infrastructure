terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "tt-tfe"

    workspaces {
      name = "infrastructure"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::548930680747:role/tt-role"
  }
}
