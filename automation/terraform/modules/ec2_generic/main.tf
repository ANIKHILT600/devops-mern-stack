variable "instance_type" {}
variable "subnet_id" {}
variable "vpc_id" {}
variable "vpc_security_group_ids" { type = list(string) }
variable "project_name" {}
variable "role_type" {}
variable "iam_instance_profile" {}
variable "key_name" { default = "" }

# Optional: Callers can supply a fully custom userdata script.
# Defaults to the minimal bootstrap (Python3 + SSM Agent) which is
# all that Ansible needs to connect and configure the server remotely.
variable "user_data_script" {
  description = "Custom userdata shell script. Defaults to minimal bootstrap."
  default     = null
}

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
  
  # Userdata: use caller-supplied script if provided, otherwise minimal bootstrap
  user_data = var.user_data_script != null ? var.user_data_script : <<-EOF
              #!/bin/bash
              # Redirect all output to a log file for debugging
              exec > /var/log/userdata.log 2>&1
              set -e

              echo "=== Starting EC2 userdata bootstrap ==="

              # Update package lists
              apt-get update -y

              # Install Python3 (mandatory for Ansible to connect and run tasks)
              apt-get install -y python3 python3-pip

              # Install SSM Agent for secure AWS Console/CLI access (no PEM key needed)
              # Ubuntu 22.04 on AWS typically has SSM pre-installed, but we ensure it here
              if ! systemctl is-active --quiet amazon-ssm-agent 2>/dev/null; then
                snap install amazon-ssm-agent --classic || true
              fi
              systemctl enable amazon-ssm-agent || true
              systemctl start amazon-ssm-agent || true

              echo "=== Userdata bootstrap complete ==="
              # Create a marker file so we can verify completion
              touch /tmp/userdata-complete
              EOF
}

output "public_ip" { value = aws_instance.server.public_ip }
output "private_ip" { value = aws_instance.server.private_ip }
output "instance_id" { value = aws_instance.server.id }
