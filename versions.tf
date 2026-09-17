terraform {
  required_version = ">= 1.11.0" # >=1.11 needed for S3 native locking (use_lockfile) in backend.tf

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
