variable "vpc_id" {}
variable "project_name" {}

# ─────────────────────────────────────────────────────────────
# JUMP SERVER SECURITY GROUP (Production VPC)
# Port 22   → SSH (Ansible access from infra-mgmt)
# Port 443  → HTTPS to EKS private endpoint (kubectl uses 443)
# Egress    → All outbound (needs to reach EKS API, ECR, AWS APIs)
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "jump_server" {
  name        = "${var.project_name}-jump-server-sg"
  description = "Security Group for Jump Server (Bastion/EKS Gateway)"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH for Ansible configuration"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for kubectl to EKS private endpoint"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (ECR pulls, AWS API calls, EKS)"
  }

  tags = { Name = "${var.project_name}-jump-server-sg" }
}

# ─────────────────────────────────────────────────────────────
# EKS WORKER NODE SECURITY GROUP (Production VPC - Private Subnets)
# self      → Node-to-node communication (pod networking)
# jump_sg   → Jump server can reach all node ports (kubectl exec,
#             port-forward, metrics scraping)
# egress    → CRITICAL: nodes need outbound to pull ECR images via
#             NAT Gateway and to reach the EKS control plane API
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "eks_node" {
  name        = "${var.project_name}-eks-node-sg"
  description = "Security Group for EKS Worker Nodes"
  vpc_id      = var.vpc_id

  # Node-to-node: all traffic (pod-to-pod, CNI overlay networking)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Node-to-node communication"
  }

  # Jump server can reach all node APIs (kubectl exec, port-forward)
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.jump_server.id]
    description     = "Jump server full access to nodes"
  }

  # CRITICAL: Without egress, nodes CANNOT:
  #   - Pull images from ECR (via NAT Gateway)
  #   - Reach EKS control plane API
  #   - Download CNI plugins
  #   - Call AWS metadata service
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Required for ECR image pulls via NAT and AWS API calls"
  }

  tags = { Name = "${var.project_name}-eks-node-sg" }
}

output "jump_server_sg_id" { value = aws_security_group.jump_server.id }
output "eks_node_sg_id" { value = aws_security_group.eks_node.id }
