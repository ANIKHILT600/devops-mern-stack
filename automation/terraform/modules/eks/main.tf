resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids = var.subnet_ids # Will pass PRIVATE subnets here
    endpoint_private_access = true
    endpoint_public_access  = true 
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "private-workers"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids # Will pass PRIVATE subnets here

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  instance_types = ["t2.medium"]
  
  # Ensure nodes can reach internet via NAT for updates/ECR
  depends_on = [
    # Implicit dependency via subnet/nat gateway in VPC module
  ]
}
