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

# ECR Repository URLs
output "ecr_frontend_url"        { value = module.ecr.repo_urls[0] }
output "ecr_backend_url"         { value = module.ecr.repo_urls[1] }

# AWS Account (for verification)
output "aws_account_id"          { value = data.aws_caller_identity.current.account_id }
