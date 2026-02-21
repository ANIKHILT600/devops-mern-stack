variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_role_arn" {
  description = "IAM Role ARN for the EKS Cluster"
  type        = string
}

variable "node_role_arn" {
  description = "IAM Role ARN for the EKS Node Group"
  type        = string
}

variable "subnet_ids" {
  description = "List of PRIVATE subnet IDs for EKS nodes (must be private — nodes are not public)"
  type        = list(string)
}

# ─────────────────────────────────────────────────────────────
# EKS CLUSTER
# endpoint_public_access = false → cluster API only reachable
# from within the VPC (jump server is the gateway)
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7
  tags = { Name = "${var.cluster_name}-cluster-logs" }
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster
  ]

  tags = { Name = var.cluster_name }
}

# ─────────────────────────────────────────────────────────────
# EKS NODE GROUP
# Nodes live in PRIVATE subnets and access ECR via NAT Gateway.
# m7i-flex.large gives good price/performance for MERN + monitoring.
#
# depends_on: AWS requires IAM role policies to be attached
# BEFORE the node group is created, otherwise nodes fail to join.
# ─────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "private-workers"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  instance_types = ["m7i-flex.large"]

  # CRITICAL: node group must wait for IAM policies to be fully attached
  # IAM propagation delay has caused node join failures without this
  depends_on = [
    aws_eks_cluster.main,
  ]
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS — Required by main.tf for Ansible inventory + kubeconfig
# ─────────────────────────────────────────────────────────────
output "cluster_name" {
  description = "EKS cluster name (used in: aws eks update-kubeconfig --name)"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS control plane security group ID (for ingress rule management)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
