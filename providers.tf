provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.cluster_name
      ManagedBy   = "terraform"
      Environment = "lab"
    }
  }
}

data "aws_caller_identity" "current" {}
