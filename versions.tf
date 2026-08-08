################################################################################
# Root - Terraform version + provider requirements
################################################################################

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# aws_profile: set to your local AWS CLI profile for local runs.
# Leave empty ("") in CI - credentials come from the OIDC role via
# environment variables (AWS_ACCESS_KEY_ID etc set by configure-aws-credentials).
variable "aws_profile" {
  type        = string
  default     = "coda-sharedservices"
  description = "AWS CLI profile for local runs. Set to empty string in CI."
}

provider "aws" {
  region  = "us-east-1"
  profile = var.aws_profile != "" ? var.aws_profile : null
}
