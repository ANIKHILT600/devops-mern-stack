variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "three-tier-app"
}

variable "cluster_name" {
  description = "EKS Cluster name"
  type        = string
  default     = "three-tier-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "jenkins_instance_type" {
  description = "Instance type for Jenkins server"
  type        = string
  default     = "m7i-flex.large"
}

variable "mgmt_instance_type" {
  description = "Instance type for Management server"
  type        = string
  default     = "m7i-flex.large"
}

variable "jump_instance_type" {
  description = "Instance type for Jump server"
  type        = string
  default     = "m7i-flex.large"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = "devops-key"
}

variable "ecr_repos" {
  description = "ECR repository names — MUST match: (1) the repo portion of 'image:' in K8s-Manifests deployments, (2) the ECR credential values in jenkins.yml Groovy, (3) the AWS_ECR_REPO_NAME used in Jenkinsfile-Backend/Frontend sed command"
  type        = list(string)
  # index 0 = frontend (→ ecr_frontend_url), index 1 = backend (→ ecr_backend_url)
  # K8s-Manifests/Backend/deployment.yaml has:  image: <account>.dkr.ecr.../backend:1
  # K8s-Manifests/Frontend/deployment.yaml has: image: <account>.dkr.ecr.../frontend:1
  # jenkins.yml Groovy sets: ECR_REPO_BACKEND=backend, ECR_REPO_FRONTEND=frontend
  default     = ["frontend", "backend"]
}
