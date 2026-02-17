variable "instance_type" {}
variable "subnet_id" {}
variable "vpc_id" {}
variable "vpc_security_group_ids" { type = list(string) }
variable "project_name" {}
variable "role_type" {}
variable "iam_instance_profile" {}
variable "key_name" { default = "" }

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.vpc_security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name

  tags = { Name = "${var.project_name}-${var.role_type}-server" }
  
  # Install SSM Agent and common tools for Ansible management
  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt-get update
              
              # Install Python for Ansible
              apt-get install -y python3 python3-pip
              
              # Install SSM Agent (for AWS Systems Manager Session Manager)
              snap install amazon-ssm-agent --classic
              systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
              systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
              
              echo "SSM Agent installed and started successfully"
              EOF
}

output "public_ip" { value = aws_instance.server.public_ip }
output "private_ip" { value = aws_instance.server.private_ip }
output "instance_id" { value = aws_instance.server.id }
