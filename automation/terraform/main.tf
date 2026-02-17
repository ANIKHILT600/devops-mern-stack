terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    local = { source = "hashicorp/local", version = "~> 2.4" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "aws" { 
  region = var.region 
}

data "aws_caller_identity" "current" {}

# ═══════════════════════════════════════════════════════════════════════
# VPC 1: MANAGEMENT VPC (10.0.0.0/16)
# Purpose: Hosts Jenkins Server and Infra Management Server
# ═══════════════════════════════════════════════════════════════════════

module "vpc_mgmt" {
  source               = "./modules/vpc"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24"]
  private_subnet_cidrs = []
  azs                  = [var.azs[0]]
  project_name         = "mgmt"
  cluster_name         = "null"
}

# ═══════════════════════════════════════════════════════════════════════
# VPC 2: PRODUCTION VPC (192.168.0.0/16)
# Purpose: Hosts Jump Server and EKS Cluster
# ═══════════════════════════════════════════════════════════════════════

module "vpc_eks" {
  source               = "./modules/vpc"
  vpc_cidr             = "192.168.0.0/16"
  public_subnet_cidrs  = ["192.168.1.0/24", "192.168.2.0/24"]
  private_subnet_cidrs = ["192.168.3.0/24", "192.168.4.0/24"]
  azs                  = var.azs
  project_name         = "prod"
  cluster_name         = var.cluster_name
}

# ═══════════════════════════════════════════════════════════════════════
# SECURITY GROUPS
# ═══════════════════════════════════════════════════════════════════════

module "sg_mgmt" {
  source       = "./modules/security_groups_mgmt"
  vpc_id       = module.vpc_mgmt.vpc_id
  project_name = "mgmt"
}

module "sg_eks" {
  source       = "./modules/security_groups_eks"
  vpc_id       = module.vpc_eks.vpc_id
  project_name = "prod"
}

# ═══════════════════════════════════════════════════════════════════════
# IAM ROLES & POLICIES
# ═══════════════════════════════════════════════════════════════════════

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
}

# ═══════════════════════════════════════════════════════════════════════
# SSH KEY PAIR
# Purpose: Allow Ansible/Jenkins to communicate with other instances
# ═══════════════════════════════════════════════════════════════════════

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${path.module}/../../ansible/private_key.pem"
  file_permission = "0600"
}

# ═══════════════════════════════════════════════════════════════════════
# AWS SYSTEMS MANAGER (SSM) VPC ENDPOINTS
# Purpose: Enable SSM Session Manager for secure, keyless EC2 access
# Production-Grade: No SSH keys needed, IAM-based access control
# ═══════════════════════════════════════════════════════════════════════

# SSM Endpoint for Management VPC
resource "aws_vpc_endpoint" "ssm_mgmt" {
  vpc_id              = module.vpc_mgmt.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_mgmt.public_subnets
  security_group_ids  = [module.sg_mgmt.mgmt_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "mgmt-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages_mgmt" {
  vpc_id              = module.vpc_mgmt.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_mgmt.public_subnets
  security_group_ids  = [module.sg_mgmt.mgmt_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "mgmt-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages_mgmt" {
  vpc_id              = module.vpc_mgmt.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_mgmt.public_subnets
  security_group_ids  = [module.sg_mgmt.mgmt_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "mgmt-ec2messages-endpoint"
  }
}

# SSM Endpoint for Production VPC
resource "aws_vpc_endpoint" "ssm_prod" {
  vpc_id              = module.vpc_eks.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_eks.public_subnets
  security_group_ids  = [module.sg_eks.jump_server_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "prod-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages_prod" {
  vpc_id              = module.vpc_eks.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_eks.public_subnets
  security_group_ids  = [module.sg_eks.jump_server_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "prod-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages_prod" {
  vpc_id              = module.vpc_eks.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_eks.public_subnets
  security_group_ids  = [module.sg_eks.jump_server_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "prod-ec2messages-endpoint"
  }
}

# ═══════════════════════════════════════════════════════════════════════
# SERVER 1: JENKINS SERVER (Management VPC)
# Purpose: CI/CD Master - Orchestrates all pipelines
# Location: Management VPC, Public Subnet
# ═══════════════════════════════════════════════════════════════════════

module "jenkins_server" {
  source                 = "./modules/ec2_generic"
  instance_type          = var.jenkins_instance_type
  subnet_id              = module.vpc_mgmt.public_subnets[0]
  vpc_id                 = module.vpc_mgmt.vpc_id
  vpc_security_group_ids = [module.sg_mgmt.jenkins_sg_id]
  project_name           = "jenkins"
  role_type              = "master"
  iam_instance_profile   = module.iam.jenkins_profile_name
  key_name               = aws_key_pair.generated_key.key_name
}

# ═══════════════════════════════════════════════════════════════════════
# SERVER 2: INFRA MANAGEMENT SERVER (Management VPC)
# Purpose: Jenkins Agent - Runs Terraform, Ansible, SonarQube, Trivy
# Location: Management VPC, Public Subnet
# ═══════════════════════════════════════════════════════════════════════

module "mgmt_server" {
  source                 = "./modules/ec2_generic"
  instance_type          = var.mgmt_instance_type
  subnet_id              = module.vpc_mgmt.public_subnets[0]
  vpc_id                 = module.vpc_mgmt.vpc_id
  vpc_security_group_ids = [module.sg_mgmt.mgmt_sg_id]
  project_name           = "infra-mgmt"
  role_type              = "tools"
  iam_instance_profile   = module.iam.jenkins_profile_name
  key_name               = aws_key_pair.generated_key.key_name
}

# ═══════════════════════════════════════════════════════════════════════
# SERVER 3: JUMP SERVER (Production VPC)
# Purpose: Bastion Host - Gateway to EKS Cluster
# Location: Production VPC, Public Subnet
# ═══════════════════════════════════════════════════════════════════════

module "jump_server" {
  source                 = "./modules/ec2_generic"
  instance_type          = var.jump_instance_type
  subnet_id              = module.vpc_eks.public_subnets[0]
  vpc_id                 = module.vpc_eks.vpc_id
  vpc_security_group_ids = [module.sg_eks.jump_server_sg_id]
  project_name           = "bastion"
  role_type              = "jump"
  iam_instance_profile   = module.iam.jenkins_profile_name
  key_name               = aws_key_pair.generated_key.key_name
}

# ═══════════════════════════════════════════════════════════════════════
# EKS CLUSTER (Production VPC)
# Purpose: Kubernetes cluster for application workloads
# Location: Production VPC, Private Subnets (Worker Nodes)
# ═══════════════════════════════════════════════════════════════════════

module "eks" {
  source           = "./modules/eks"
  cluster_name     = var.cluster_name
  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn
  subnet_ids       = module.vpc_eks.private_subnets
}

# ═══════════════════════════════════════════════════════════════════════
# ECR REPOSITORIES
# Purpose: Private Docker image registry
# ═══════════════════════════════════════════════════════════════════════

module "ecr" {
  source     = "./modules/ecr"
  repo_names = var.ecr_repos
}

# ═══════════════════════════════════════════════════════════════════════
# ANSIBLE INVENTORY GENERATION
# Purpose: Dynamically create Ansible inventory from Terraform outputs
# ═══════════════════════════════════════════════════════════════════════

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    mgmt_ip          = module.mgmt_server.public_ip
    jenkins_ip       = module.jenkins_server.public_ip
    jump_ip          = module.jump_server.public_ip
    mgmt_private_ip  = module.mgmt_server.private_ip
    cluster_name     = var.cluster_name
    region           = var.region
    ecr_frontend_url = module.ecr.repo_urls[0]
    ecr_backend_url  = module.ecr.repo_urls[1]
    account_id       = data.aws_caller_identity.current.account_id
  })
  filename = "${path.module}/../../ansible/inventory.ini"
}
