# The bucket below must exist BEFORE `terraform init` -- see RUNBOOK.md Step 0.
# Backend blocks can't reference variables, so region/bucket are hardcoded here.
#
# use_lockfile = true is native S3 locking (Terraform >= 1.11), replacing the
# older DynamoDB lock table.
terraform {
  backend "s3" {
    bucket       = "gavok-zt-tfstate"
    key          = "gavok-zt-foundation/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
