data "aws_caller_identity" "current" {}

# ═══════════════════════════════════════════════════════════════════════
# VPC 1: MANAGEMENT VPC (10.0.0.0/16)
# Purpose: Hosts Jenkins Server and Infra Management Server
# ═══════════════════════════════════════════════════════════════════════

module "vpc_mgmt" {
  source               = "./modules/vpc"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24"]
  private_subnet_cidrs = []
  azs                  = [var.azs[0]]
  project_name         = "mgmt"
  cluster_name         = "null"
}

# ═══════════════════════════════════════════════════════════════════════
# VPC 2: PRODUCTION VPC (192.168.0.0/16)
# Purpose: Hosts Jump Server and EKS Cluster
# ═══════════════════════════════════════════════════════════════════════

module "vpc_eks" {
  source               = "./modules/vpc"
  vpc_cidr             = "192.168.0.0/16"
  public_subnet_cidrs  = ["192.168.1.0/24", "192.168.2.0/24"]
  private_subnet_cidrs = ["192.168.3.0/24", "192.168.4.0/24"]
  azs                  = var.azs
  project_name         = "prod"
  cluster_name         = var.cluster_name
}

# ═══════════════════════════════════════════════════════════════════════
# SECURITY GROUPS
# ═══════════════════════════════════════════════════════════════════════

module "sg_mgmt" {
  source       = "./modules/security_groups_mgmt"
  vpc_id       = module.vpc_mgmt.vpc_id
  project_name = "mgmt"
}

module "sg_eks" {
  source       = "./modules/security_groups_eks"
  vpc_id       = module.vpc_eks.vpc_id
  project_name = "prod"
}

# ═══════════════════════════════════════════════════════════════════════
# IAM ROLES & POLICIES
# ═══════════════════════════════════════════════════════════════════════

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
}

# ═══════════════════════════════════════════════════════════════════════
# SSH KEY PAIR
# Purpose: Allow Ansible/Jenkins to communicate with other instances
# ═══════════════════════════════════════════════════════════════════════

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${path.module}/../ansible/private_key.pem"
  file_permission = "0600"
}

# ═══════════════════════════════════════════════════════════════════════
# AWS SYSTEMS MANAGER (SSM) VPC ENDPOINTS
# Purpose: Enable SSM Session Manager for secure, keyless EC2 access
# Production-Grade: No SSH keys needed, IAM-based access control
# ═══════════════════════════════════════════════════════════════════════

# SSM Endpoint for Management VPC
resource "aws_vpc_endpoint" "ssm_mgmt" {
  vpc_id              = module.vpc_mgmt.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_mgmt.public_subnets
  security_group_ids  = [module.sg_mgmt.mgmt_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "mgmt-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages_mgmt" {
  vpc_id              = module.vpc_mgmt.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_mgmt.public_subnets
  security_group_ids  = [module.sg_mgmt.mgmt_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "mgmt-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages_mgmt" {
  vpc_id              = module.vpc_mgmt.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_mgmt.public_subnets
  security_group_ids  = [module.sg_mgmt.mgmt_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "mgmt-ec2messages-endpoint"
  }
}

# SSM Endpoint for Production VPC
resource "aws_vpc_endpoint" "ssm_prod" {
  vpc_id              = module.vpc_eks.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_eks.public_subnets
  security_group_ids  = [module.sg_eks.jump_server_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "prod-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages_prod" {
  vpc_id              = module.vpc_eks.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_eks.public_subnets
  security_group_ids  = [module.sg_eks.jump_server_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "prod-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages_prod" {
  vpc_id              = module.vpc_eks.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_eks.public_subnets
  security_group_ids  = [module.sg_eks.jump_server_sg_id]
  private_dns_enabled = true

  tags = {
    Name = "prod-ec2messages-endpoint"
  }
}

# ═══════════════════════════════════════════════════════════════════════
# SERVER 1: JENKINS SERVER (Management VPC)
# Purpose: CI/CD Master - Orchestrates all pipelines
# Location: Management VPC, Public Subnet
# ═══════════════════════════════════════════════════════════════════════

module "jenkins_server" {
  source                 = "./modules/ec2_generic"
  instance_type          = var.jenkins_instance_type
  subnet_id              = module.vpc_mgmt.public_subnets[0]
  vpc_id                 = module.vpc_mgmt.vpc_id
  vpc_security_group_ids = [module.sg_mgmt.jenkins_sg_id]
  project_name           = "jenkins"
  role_type              = "master"
  iam_instance_profile   = module.iam.jenkins_profile_name
  key_name               = aws_key_pair.generated_key.key_name
}

# ═══════════════════════════════════════════════════════════════════════
# SERVER 2: INFRA MANAGEMENT SERVER (Management VPC)
# Purpose: Jenkins Agent - Runs Terraform, Ansible, SonarQube, Trivy
# Location: Management VPC, Public Subnet
#
# KEY DESIGN: All tools are installed via userdata at boot time.
# This means ZERO local Ansible is needed to bootstrap this server.
# After boot (~10 mins), all tools are ready. Ansible is then used
# FROM THIS SERVER to configure Jenkins Server, Jump Server, and EKS.
# ═══════════════════════════════════════════════════════════════════════

locals {
  mgmt_server_userdata = <<-USERDATA
    #!/bin/bash
    # ─────────────────────────────────────────────────────────────────
    # infra-mgmt-server bootstrap: installs ALL DevSecOps tools at boot
    # Log everything for debugging: cat /var/log/userdata.log
    # Completion marker: /tmp/userdata-complete
    # ─────────────────────────────────────────────────────────────────
    exec > /var/log/userdata.log 2>&1

    # Trap errors: log the failing line number instead of a silent exit
    set -euo pipefail
    trap 'echo "=== ERROR: Script failed at line $LINENO. Check /var/log/userdata.log ===" >&2' ERR

    echo "=== [1/10] Updating system packages ==="
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y \
      wget curl unzip git gnupg lsb-release \
      software-properties-common apt-transport-https ca-certificates \
      python3 python3-pip python3-venv openjdk-17-jre

    echo "=== [2/10] Installing SSM Agent ==="
    if ! systemctl is-active --quiet amazon-ssm-agent 2>/dev/null; then
      snap install amazon-ssm-agent --classic || true
    fi
    systemctl enable amazon-ssm-agent || true
    systemctl start amazon-ssm-agent || true

    echo "=== [3/10] Installing Terraform ==="
    wget -O- https://apt.releases.hashicorp.com/gpg | \
      gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
      https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update -y && apt-get install -y terraform

    echo "=== [4/10] Installing Ansible + AWS Python libs ==="
    # Ubuntu 22.04 (Jammy) ships pip 22.0.x which does NOT support
    # --break-system-packages. Use a dedicated virtualenv instead.
    python3 -m venv /opt/devops-venv
    /opt/devops-venv/bin/pip install --upgrade pip
    /opt/devops-venv/bin/pip install ansible boto3 botocore

    # Symlink binaries so they are on PATH system-wide
    ln -sf /opt/devops-venv/bin/ansible       /usr/local/bin/ansible
    ln -sf /opt/devops-venv/bin/ansible-playbook /usr/local/bin/ansible-playbook
    ln -sf /opt/devops-venv/bin/ansible-galaxy   /usr/local/bin/ansible-galaxy

    # Make ubuntu user's shell use the venv Python (for boto3 imports etc.)
    echo 'source /opt/devops-venv/bin/activate' >> /home/ubuntu/.bashrc

    # Install required Ansible collections as ubuntu user
    su - ubuntu -c "source /opt/devops-venv/bin/activate && ansible-galaxy collection install community.docker amazon.aws community.general --upgrade" || true

    echo "=== [5/10] Installing AWS CLI v2 ==="
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --update
    rm -rf /tmp/aws /tmp/awscliv2.zip

    echo "=== [6/10] Installing Docker CE ==="
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    chmod 660 /var/run/docker.sock

    echo "=== [7/10] Setting vm.max_map_count for SonarQube ==="
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf

    echo "=== [7.5/10] Creating Docker Persistent Volume for SonarQube ==="
    # Create a named Docker volume for SonarQube data persistence
    # Docker volumes are managed by Docker daemon and persist across container restarts
    docker volume create sonarqube_data || true

    echo "=== [8/10] Starting SonarQube container with Docker persistent volume ==="
    # Use Docker named volume instead of bind mount (more portable, Docker-native)
    # sonarqube_data → Docker volume name
    # /var/lib/sonarqube → Container path where SonarQube stores data
    docker run -d \
      --name sonar \
      --restart unless-stopped \
      -p 9000:9000 \
      -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
      -v sonarqube_data:/var/lib/sonarqube \
      sonarqube:lts-community

    # Verify volume was mounted
    docker inspect sonar | grep -A 3 Mounts | head -5

    echo "=== [9/10] Installing Trivy ==="
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
      gpg --dearmor -o /usr/share/keyrings/trivy-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/trivy-keyring.gpg] \
      https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
      | tee /etc/apt/sources.list.d/trivy.list
    apt-get update -y && apt-get install -y trivy

    echo "=== [10/10] Creating Jenkins Agent workspace ==="
    mkdir -p /home/ubuntu/jenkins_agent
    chown ubuntu:ubuntu /home/ubuntu/jenkins_agent

    echo "=== Userdata bootstrap COMPLETE ==="
    touch /tmp/userdata-complete
  USERDATA
}

module "mgmt_server" {
  source                 = "./modules/ec2_generic"
  instance_type          = var.mgmt_instance_type
  subnet_id              = module.vpc_mgmt.public_subnets[0]
  vpc_id                 = module.vpc_mgmt.vpc_id
  vpc_security_group_ids = [module.sg_mgmt.mgmt_sg_id]
  project_name           = "infra-mgmt"
  role_type              = "tools"
  iam_instance_profile   = module.iam.jenkins_profile_name
  key_name               = aws_key_pair.generated_key.key_name
  user_data_script       = local.mgmt_server_userdata
}

# ═══════════════════════════════════════════════════════════════════════
# SERVER 3: JUMP SERVER (Production VPC)
# Purpose: Bastion Host - Gateway to EKS Cluster
# Location: Production VPC, Public Subnet
# ═══════════════════════════════════════════════════════════════════════

module "jump_server" {
  source                 = "./modules/ec2_generic"
  instance_type          = var.jump_instance_type
  subnet_id              = module.vpc_eks.public_subnets[0]
  vpc_id                 = module.vpc_eks.vpc_id
  vpc_security_group_ids = [module.sg_eks.jump_server_sg_id]
  project_name           = "bastion"
  role_type              = "jump"
  iam_instance_profile   = module.iam.jenkins_profile_name
  key_name               = aws_key_pair.generated_key.key_name
}

# ═══════════════════════════════════════════════════════════════════════
# EKS CLUSTER (Production VPC)
# Purpose: Kubernetes cluster for application workloads
# Location: Production VPC, Private Subnets (Worker Nodes)
# ═══════════════════════════════════════════════════════════════════════

module "eks" {
  source           = "./modules/eks"
  cluster_name     = var.cluster_name
  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn
  subnet_ids       = module.vpc_eks.private_subnets
}

# ═══════════════════════════════════════════════════════════════════════
# ECR REPOSITORIES
# Purpose: Private Docker image registry
# ═══════════════════════════════════════════════════════════════════════

module "ecr" {
  source     = "./modules/ecr"
  repo_names = var.ecr_repos
}

# ═══════════════════════════════════════════════════════════════════════
# ANSIBLE INVENTORY GENERATION
# Purpose: Dynamically create Ansible inventory from Terraform outputs
# ═══════════════════════════════════════════════════════════════════════

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    mgmt_ip          = module.mgmt_server.public_ip
    jenkins_ip       = module.jenkins_server.public_ip
    jump_ip          = module.jump_server.public_ip
    mgmt_private_ip  = module.mgmt_server.private_ip
    cluster_name     = var.cluster_name
    region           = var.region
    ecr_frontend_url = module.ecr.repo_urls[0]
    ecr_backend_url  = module.ecr.repo_urls[1]
    account_id       = data.aws_caller_identity.current.account_id
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
