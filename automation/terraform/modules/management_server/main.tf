variable "instance_type" {}
variable "subnet_id" {}
variable "vpc_id" {}
variable "key_name" {}
variable "private_key_path" {}
variable "project_name" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

resource "aws_security_group" "mgmt" {
  name        = "${var.project_name}-mgmt-sg"
  description = "Security Group for Management Server"
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

  tags = { Name = "${var.project_name}-mgmt-sg" }
}

resource "aws_iam_role" "mgmt" {
  name = "${var.project_name}-mgmt-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.mgmt.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "mgmt" {
  name = "${var.project_name}-mgmt-profile"
  role = aws_iam_role.mgmt.name
}

resource "aws_instance" "mgmt" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.mgmt.id]
  iam_instance_profile   = aws_iam_instance_profile.mgmt.name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y unzip curl git software-properties-common

              # Install Terraform (Fixed GPG Key issue)
              wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
              echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
              apt-get update && apt-get install terraform -y

              # Install Ansible
              apt-add-repository ppa:ansible/ansible -y
              apt-get update
              apt-get install ansible -y

              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install

              echo "DevSecOps Tooling Server Ready"
              EOF

  tags = { Name = "${var.project_name}-mgmt-server" }
}

output "public_ip" { value = aws_instance.mgmt.public_ip }
