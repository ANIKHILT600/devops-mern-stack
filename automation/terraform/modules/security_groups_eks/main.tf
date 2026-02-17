variable "vpc_id" {}
variable "project_name" {}

resource "aws_security_group" "jump_server" {
  name        = "${var.project_name}-jump-server-sg"
  description = "Security Group for Jump Server"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-jump-server-sg" }
}

resource "aws_security_group" "eks_node" {
  name        = "${var.project_name}-eks-node-sg"
  description = "Security Group for EKS Worker Nodes"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.jump_server.id]
  }

  tags = { Name = "${var.project_name}-eks-node-sg" }
}

output "jump_server_sg_id" { value = aws_security_group.jump_server.id }
output "eks_node_sg_id" { value = aws_security_group.eks_node.id }
