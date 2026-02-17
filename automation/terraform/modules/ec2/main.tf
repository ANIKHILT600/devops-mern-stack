variable "jenkins_instance_type" {}
variable "jump_instance_type" {}
variable "subnet_id" {}
variable "jenkins_sg_id" {}
variable "jump_sg_id" {}
variable "iam_instance_profile" {}
variable "key_name" {}
variable "private_key_path" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = var.key_name
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.pk.private_key_pem
  filename        = var.private_key_path
  file_permission = "0400"
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.jenkins_instance_type
  key_name               = aws_key_pair.generated.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.jenkins_sg_id]
  iam_instance_profile   = var.iam_instance_profile

  tags = { Name = "Jenkins-Server" }
}

resource "aws_instance" "jump" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.jump_instance_type
  key_name               = aws_key_pair.generated.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.jump_sg_id]
  iam_instance_profile   = var.iam_instance_profile

  tags = { Name = "Jump-Server" }
}

output "jenkins_public_ip" { value = aws_instance.jenkins.public_ip }
output "jump_public_ip" { value = aws_instance.jump.public_ip }
