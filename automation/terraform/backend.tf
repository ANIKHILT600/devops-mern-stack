# ═══════════════════════════════════════════════════════════════════════
# TERRAFORM S3 REMOTE STATE BACKEND
#
# WHY: - Stores tfstate in AWS S3 (safe, versioned, encrypted)
#       - DynamoDB provides state locking (prevents concurrent runs)
#       - Allows infra-mgmt-server and Jenkins to share the same state
#
# PREREQUISITE (one-time manual step from local before first apply):
#   aws s3api create-bucket --bucket three-tier-app-tfstate-<YOUR_ACCOUNT_ID> \
#     --region us-east-1
#   aws s3api put-bucket-versioning --bucket three-tier-app-tfstate-<YOUR_ACCOUNT_ID> \
#     --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket three-tier-app-tfstate-<YOUR_ACCOUNT_ID> \
#     --server-side-encryption-configuration \
#     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#   aws dynamodb create-table --table-name three-tier-app-tflock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region us-east-1
# ═══════════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    # IMPORTANT: Replace <YOUR_ACCOUNT_ID> with your actual AWS Account ID e.g., bucket = "three-tier-app-tfstate-123456789012"
    bucket         = "three-tier-app-tfstate-748787803760"
    key            = "devops-mern-stack/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "three-tier-app-tflock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.5.0"
}
