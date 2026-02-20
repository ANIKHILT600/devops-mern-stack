# NOTE: The terraform{} block (required_providers + backend) is defined
# in backend.tf. Only the provider configuration lives here.

provider "aws" {
  region = var.region
}

