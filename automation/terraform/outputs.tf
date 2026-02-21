output "infra_mgmt_server_ip"    { value = module.mgmt_server.public_ip }
output "jenkins_server_ip"       { value = module.jenkins_server.public_ip }
output "jump_server_ip"          { value = module.jump_server.public_ip }

output "infra_mgmt_private_ip"   { value = module.mgmt_server.private_ip }
output "jenkins_private_ip"      { value = module.jenkins_server.private_ip }
output "jump_server_private_ip"  { value = module.jump_server.private_ip }

output "infra_mgmt_instance_id"  { value = module.mgmt_server.instance_id }
output "jenkins_instance_id"     { value = module.jenkins_server.instance_id }
output "jump_server_instance_id" { value = module.jump_server.instance_id }

# EKS Cluster outputs (now available after eks/main.tf fix)
output "eks_cluster_name"        { value = module.eks.cluster_name }
output "eks_cluster_endpoint"    { value = module.eks.cluster_endpoint }
output "eks_cluster_security_group_id" { 
  description = "EKS control plane security group (for debugging)"
  value       = module.eks.cluster_security_group_id 
}

# ECR Repository URLs
output "ecr_frontend_url"        { value = module.ecr.repo_urls[0] }
output "ecr_backend_url"         { value = module.ecr.repo_urls[1] }

# AWS Account (for verification)
output "aws_account_id"          { value = data.aws_caller_identity.current.account_id }

# ═══════════════════════════════════════════════════════════════════════
# VPC PEERING & NETWORKING
# ═══════════════════════════════════════════════════════════════════════

output "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID (mgmt ↔ prod)"
  value       = aws_vpc_peering_connection.mgmt_to_prod.id
}

output "vpc_peering_status" {
  description = "VPC Peering Status (should be 'active')"
  value       = aws_vpc_peering_connection.mgmt_to_prod.accept_status
}

# ═══════════════════════════════════════════════════════════════════════
# MANAGEMENT VPC NETWORKING
# ═══════════════════════════════════════════════════════════════════════

output "mgmt_vpc_id" {
  description = "Management VPC ID (Jenkins, Infra server)"
  value       = module.vpc_mgmt.vpc_id
}

output "mgmt_vpc_cidr" {
  description = "Management VPC CIDR block"
  value       = "10.0.0.0/16"
}

output "prod_vpc_id" {
  description = "Production VPC ID (EKS, Jump server)"
  value       = module.vpc_eks.vpc_id
}

output "prod_vpc_cidr" {
  description = "Production VPC CIDR block"
  value       = "192.168.0.0/16"
}

# ═══════════════════════════════════════════════════════════════════════
# EKS LOGGING & MONITORING
# ═══════════════════════════════════════════════════════════════════════

output "eks_cloudwatch_log_group" {
  description = "CloudWatch log group for EKS control plane logs (audit trail)"
  value       = "/aws/eks/${module.eks.cluster_name}/cluster"
}

# ═══════════════════════════════════════════════════════════════════════
# SONARQUBE PERSISTENCE (Docker Volume)
# ═══════════════════════════════════════════════════════════════════════

output "sonarqube_docker_volume" {
  description = "Docker volume name for SonarQube data persistence"
  value       = "sonarqube_data"
}

output "sonarqube_container_mount_path" {
  description = "SonarQube container mount path for persistent data"
  value       = "/var/lib/sonarqube"
}

# ═══════════════════════════════════════════════════════════════════════
# SECURITY GROUP REFERENCES
# ═══════════════════════════════════════════════════════════════════════

output "jenkins_security_group_id" {
  description = "Jenkins server security group"
  value       = module.sg_mgmt.jenkins_sg_id
}

output "mgmt_security_group_id" {
  description = "Management server security group"
  value       = module.sg_mgmt.mgmt_sg_id
}

output "jump_server_security_group_id" {
  description = "Jump server security group (EKS gateway)"
  value       = module.sg_eks.jump_server_sg_id
}

# ═══════════════════════════════════════════════════════════════════════
# OIDC PROVIDER (Managed by Ansible via eksctl)
# ═══════════════════════════════════════════════════════════════════════

output "oidc_issuer_url" {
  description = "EKS OIDC issuer URL (for IRSA role configuration post-deployment)"
  value       = try(
    replace(module.eks.cluster_endpoint, "/https.*control/", ""),
    "https://${replace(module.eks.cluster_endpoint, "https://", "")}:443"
  )
  # Note: This is an approximate value. The actual OIDC provider is installed by Ansible
  # Use: aws eks describe-cluster --name <cluster> --query 'cluster.identity.oidc.issuer'
}
