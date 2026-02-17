# Production-Ready DevSecOps Automation Implementation Guide

## 📋 Table of Contents

1. [Executive Summary](#executive-summary)
2. [Infrastructure Components](#infrastructure-components)
3. [Security & Monitoring](#security--monitoring)
4. [Automated Workflow & Execution Order](#automated-workflow--execution-order)
5. [Step-by-Step Implementation](#step-by-step-implementation)
6. [Automatic vs Manual Implementation Mapping](#automatic-vs-manual-implementation-mapping)
7. [Access URLs & Verification](#access-urls--verification)
8. [Production Readiness Checklist](#production-readiness-checklist)

---

## 🎯 Executive Summary

This automation implements a **fully automated, production-grade DevSecOps pipeline** that provisions cloud infrastructure, configures servers, and deploys a three-tier application with integrated security and monitoring.

### What We're Building (Automatically)

- **2 Isolated VPCs** (Management + Production) for network segmentation.
- **3 Specialized EC2 Servers**:
  - **Jenkins Server**: CI/CD Master (Orchestrator).
  - **Infra Management Server**: Jenkins Agent + Tools (Terrorform, Ansible, SonarQube, Trivy).
  - **Jump Server**: Secure Bastion Host for EKS access.
- **1 EKS Cluster** with worker nodes in private subnets.
- **Complete CI/CD Pipeline** with:
  - **Static Code Analysis** (SonarQube)
  - **Vulnerability Scanning** (Trivy - FS & Image)
  - **Docker Build & Push** (ECR)
  - **GitOps Deployment** (ArgoCD)
- **Monitoring Stack**: Prometheus & Grafana (in EKS).
- **Secure Access**:
  - **AWS SSM Session Manager**: For human access (No SSH keys required).
  - **Internal SSH**: For machine-to-machine communication (Jenkins -> Agent), fully automated via Terraform-generated keys.

---


## 🖥️ Infrastructure Components

### 1. Jenkins Server (CI/CD Master)
- **Role**: Orchestrator. It delegates all heavy lifting to the Agent.
- **Configuration**:
  - Installed via Ansible (`jenkins.yml`).
  - **Plugins**: Git, Pipeline, SonarQube, AWS Credentials, SSH Slaves.
  - **Auto-Configuration**:
    - Admin User created automatically.
    - **Jenkins Agent** (`infra-mgmt`) automatically registered via Groovy script.
    - **Credentials** (GitHub, AWS, Sonar, SSH Key) automatically injected.

### 2. Infra Management Server (The "Workhorse")
- **Role**: Jenkins Agent & Tool Host.
- **Why Separate?**: Keeps Jenkins master clean and responsive.
- **Tools Installed**:
  - **Terraform**: For provisioning.
  - **Ansible**: For configuration.
  - **SonarQube**: Docker container running on port 9000.
  - **Trivy**: For security scanning.
  - **Docker**: For building images.
  - **AWS CLI**: For ECR/EKS interaction.

### 3. Jump Server (Bastion)
- **Role**: Gateway to EKS.
- **Tools**: `kubectl`, `eksctl`, `helm`.
- **Purpose**: Since EKS nodes are in private subnets, this server handles all cluster configuration commands (installing ArgoCD, Prometheus, etc.).

---

## ⚙️ Automated Workflow & Execution Order

The entire setup is orchestrated in two main phases:

### Phase 1: Infrastructure Provisioning (Terraform)
*Duration: ~25 mins*

1. **Generate Keys**: Creates SSH key pair for internal communication.
2. **Network**: VPCs, Subnets, Gateways, Route Tables, Security Groups.
3. **IAM**: Roles and Profiles for EC2 and EKS.
4. **Compute**: EC2 Instances (Jenkins, Mgmt, Jump) with User Data to install SSM Agent.
5. **EKS**: Cluster Control Plane and Node Groups (Private).
6. **Outputs**: Generates `inventory.ini` and `private_key.pem` for Ansible.

### Phase 2: Configuration Management (Ansible)
*Duration: ~35 mins*

1. **Infra Mgmt Server** (`mgmt_server.yml`):
   - Installs Docker, starts SonarQube container.
   - Installs Terraform, Ansible, Trivy.
2. **Jenkins Server** (`jenkins.yml`):
   - Installs Jenkins & Java.
   - **Crucial Step**: Runs Groovy scripts to:
     - Create Admin User.
     - Add `infra-ssh-key` credential using the Terraform-generated key.
     - Add all other API credentials (AWS, GitHub, Sonar).
     - **Create 'infra-mgmt' Node**: Connects Jenkins to the Mgmt server automatically.
3. **Jump Server** (`jump_server.yml`):
   - Installs k8s tools.
   - Configures `kubeconfig` to access the EKS cluster.
4. **EKS Setup** (`eks.yml`):
   - Uses Jump Server to deploy:
     - AWS Load Balancer Controller.
     - ArgoCD (GitOps).
     - Prometheus & Grafana.
     - Application Namespaces (`three-tier`).

---

## 📖 Step-by-Step Implementation

### Prerequisites
- AWS Account with Administrator Access.
- GitHub Account & Personal Access Token (Classic).
- AWS CloudShell (Recommended) or Local Terminal with AWS CLI & Terraform installed.

### Step 1: Clone & Initialize

**1. Why?**  
To get the automation code that defines our infrastructure.

**2. Where?**  
On your **Local Machine's Terminal** or **AWS CloudShell**.

**3. How?**  
Run the following commands:
```bash
# Clone the repository
git clone https://github.com/ANIKHILT600/devops-mern-stack.git

# Navigate to the Terraform directory
cd devops-mern-stack/automation/terraform
```

**4. Result**  
You now have the project files and are in the correct directory.

---

### Step 2: Provision Infrastructure (Terraform)

**1. Why?**  
To actually create the servers, network, and EKS cluster in AWS.

**2. Where?**  
From the same **automation/terraform** directory.

**3. How?**  
```bash
# Initialize Terraform (downloads AWS plugins)
terraform init

# Apply the plan (creates resources)
# Type 'yes' if not using auto-approve, or use this flag:
terraform apply --auto-approve
```
*Wait time: Approx 20-25 minutes.*

**4. Result**  
- **3 EC2 Instances Running**: Jenkins, Infra Mgmt, Jump Server.
- **1 EKS Cluster Active**: In private subnets.
- **Files Created**: `../ansible/inventory.ini` (Server list) and `../ansible/private_key.pem` (Access key).

---

### Step 3: Configure Servers (Ansible)

**1. Why?**  
To install software (Jenkins, Docker, SonarQube, etc.) on the blank servers we just created.

**2. Where?**  
From the **automation/ansible** directory (navigate up: `cd ../ansible`).

**3. How?**

#### 3A. Install Ansible & Dependencies (One-Time)
If in CloudShell/New Machine, install tools first:
```bash
sudo pip3 install ansible
pip3 install boto3 botocore
ansible-galaxy collection install amazon.aws community.general
```

#### 3B. Start SonarQube First
We need SonarQube running to get a token for Jenkins.
```bash
# Run ONLY the management server playbook
ansible-playbook -i inventory.ini mgmt_server.yml
```

#### 3C. Get SonarQube Token
1. **Get IP**: Run `cd ../terraform && terraform output infra_mgmt_server_ip`
2. **Open Browser**: `http://<INFRA_MGMT_IP>:9000`
3. **Login**: `admin` / `admin` (change password if asked).
4. **Generate Token**:
   - Click User Icon (top right) -> My Account -> Security.
   - Name: `jenkins-token` -> Click Generate.
   - **COPY THIS TOKEN**.

#### 3D. Create SonarQube Webhook
1. Go to **Administration** (top bar) -> **Configuration** -> **Webhooks**.
2. Click **Create**.
3. Name: `jenkins`
4. URL: `http://<JENKINS_SERVER_IP>:8080/sonarqube-webhook/`
   *(Get Jenkins IP from `terraform output jenkins_server_ip`)*.
5. Click **Create**.

#### 3E. Configure Everything Else
Now pass your secrets to configure Jenkins and the cluster.

```bash
cd ../ansible

# Export secrets (REPLACE VALUES WITH YOURS)
export GIT_TOKEN="ghp_YOUR_GITHUB_TOKEN"
export SONAR_TOKEN="squ_YOUR_SONAR_TOKEN_FROM_ABOVE"
export AWS_ACCESS="YOUR_AWS_ACCESS_KEY"
export AWS_SECRET="YOUR_AWS_SECRET_KEY"
export AWS_ID="$(aws sts get-caller-identity --query Account --output text)"

# Run configuration for Jenkins, Jump Server, and EKS
ansible-playbook -i inventory.ini jenkins.yml \
  --extra-vars "sonar_token=$SONAR_TOKEN github_token=$GIT_TOKEN \
  github_username=anikhilt600 aws_access_key=$AWS_ACCESS \
  aws_secret_key=$AWS_SECRET aws_account_id=$AWS_ID"

ansible-playbook -i inventory.ini jump_server.yml
ansible-playbook -i inventory.ini eks.yml
```

**4. Result**  
- **Jenkins**: Completely configured with Admin user, Agent connected, and Credentials added.
- **EKS**: Has ArgoCD, Prometheus, Grafana installed.
- **Jump Server**: Ready to control EKS.

---

### Step 4: Run Pipelines

**1. Why?**  
To deploy your application code to the EKS cluster.

**2. Where?**  
**Jenkins Web UI**.

**3. How?**

**CRITICAL**: The Master pipeline triggers other jobs. You must create **ALL 4** jobs below manually first.

#### 4A. Create `Infra-Provisioning` Job
1. **New Item** -> Name: `Infra-Provisioning` -> Type: **Pipeline**.
2. **Pipeline Definition**: **Pipeline script from SCM**.
3. **SCM**: Git -> URL: `https://github.com/ANIKHILT600/devops-mern-stack.git` -> Branch: `*/main`
4. **Script Path**: `automation/jenkins/Jenkinsfile.infra`
5. **Save**.

#### 4B. Create `App-Deploy-Backend` Job
1. **New Item** -> Name: `App-Deploy-Backend` -> Type: **Pipeline**.
2. **Pipeline Definition**: **Pipeline script from SCM**.
3. **SCM**: Git -> URL: `https://github.com/ANIKHILT600/devops-mern-stack.git` -> Branch: `*/main`
4. **Script Path**: `automation/jenkins/Jenkinsfile.backend`
5. **Save**.

#### 4C. Create `App-Deploy-Frontend` Job
1. **New Item** -> Name: `App-Deploy-Frontend` -> Type: **Pipeline**.
2. **Pipeline Definition**: **Pipeline script from SCM**.
3. **SCM**: Git -> URL: `https://github.com/ANIKHILT600/devops-mern-stack.git` -> Branch: `*/main`
4. **Script Path**: `automation/jenkins/Jenkinsfile.frontend`
5. **Save**.

#### 4D. Create & Run `DevSecOps-Master` Job
1. **New Item** -> Name: `DevSecOps-Master` -> Type: **Pipeline**.
2. **Pipeline Definition**: **Pipeline script from SCM**.
3. **SCM**: Git -> URL: `https://github.com/ANIKHILT600/devops-mern-stack.git` -> Branch: `*/main`
4. **Script Path**: `automation/jenkins/Jenkinsfile.master`
5. **Save**.

**Now, Trigger it:**
- Go to `DevSecOps-Master` -> Click **Build Now**.

**4. Result**  
The Master pipeline will automatically trigger `Infra-Provisioning`, then wait, then trigger `Backend` and `Frontend` in parallel. After ~20 mins, your app will be live!

---

## 🔄 Automatic vs Manual Implementation Mapping

Here is how every step in the [Manual_Implementation.md](../Manual_Implementation.md) is handled by this automation:

| Manual Step | Automated Solution | How It Works |
|-------------|--------------------|--------------|
| **1. IAM User Setup** | `terraform/modules/iam` | Creates IAM Roles for EC2/EKS defined in Terraform. |
| **2. Create Jenkins Server** | `terraform/modules/ec2_generic` | Provisions EC2 with UserData for SSM agent. |
| **3. Configure Jenkins** | `ansible/jenkins.yml` | Installs Java, Jenkins, Plugins via Apt/CLI. **Automates Agent connection via Groovy.** |
| **4. Deploy EKS (eksctl)** | `terraform/modules/eks` | Uses Terraform AWS Provider to create EKS (more stable than eksctl). |
| **5. Create Jump Server** | `terraform/modules/ec2_generic` | Provisions EC2 in Production VPC. |
| **6. Validate Connectivity** | `ansible/jump_server.yml` | Installs kubectl and sets up kubeconfig on Jump Server automatically. |
| **7. AWS LB Controller** | `ansible/eks.yml` | Uses Helm to install the controller on EKS via Jump Server. |
| **8. Configure SonarQube** | `ansible/mgmt_server.yml` | Runs SonarQube Docker container on Mgmt Server. |
| **9. Create ECR Repos** | `terraform/modules/ecr` | Creates ECR repositories via Terraform. |
| **10. Jenkins Credentials** | `ansible/jenkins.yml` | **Groovy Script** injects AWS, GitHub, Sonar credentials into Jenkins Keystore. |
| **11. Build Pipelines** | `Jenkinsfile.{backend,frontend}` | Defined as Code. Uses the 'infra-mgmt' agent for execution. |
| **12. Install ArgoCD** | `ansible/eks.yml` | Uses `kubectl apply` to install ArgoCD manifests. |
| **13. Deploy 3-Tier App** | `ansible/eks.yml` | Applies ArgoCD Application manifests (`argocd-apps.yaml`) to trigger gitops sync. |
| **14. Configure DNS** | `terraform/modules/vpc` | VPC DNS settings enabled by default. |
| **15. Prometheus/Grafana** | `ansible/eks.yml` | Uses Helm to install full monitoring stack on EKS. |

---

## 🌐 Access URLs & Verification

### Important: DNS Configuration
The application Ingress is configured to listen **ONLY** for the domain `tarangan4u.dpdns.org`.
Since this domain likely doesn't point to your new Load Balancer, you must "fake" it locally.

#### step 1: Get the Load Balancer DNS
In Jenkins, the **DevSecOps-Master** build description will show the URL.
Or run this on the Jump Server:
```bash
kubectl get ingress -n three-tier
# Copy the ADDRESS (e.g., k8s-threetie-mainlb-xxxx.us-east-1.elb.amazonaws.com)
```

#### Step 2: Get the IP Address
Run this on your local terminal:
```bash
nslookup k8s-threetie-mainlb-xxxx.us-east-1.elb.amazonaws.com
# Copy one of the "Address" IPs (e.g., 34.1.2.3)
```

#### Step 3: Update Hosts File (The "Hack")
Map the domain to that IP on your local machine.

- **Windows**: Open Notepad as Admin. Edit `C:\Windows\System32\drivers\etc\hosts`.
- **Mac/Linux**: `sudo nano /etc/hosts`

Add this line along with IP you got from above nslookup command:
```
34.1.2.3  tarangan4u.dpdns.org
```

#### Step 4: Access in Browser
Now open: **[http://tarangan4u.dpdns.org](http://tarangan4u.dpdns.org)**
- You should see the Frontend.
- It will successfully talk to the Backend because the Ingress handles routing based on paths (`/` and `/api`).

---

### Verification Checklist

After the **DevSecOps-Master-Pipeline** completes:

1. **Grafana**: Access via LoadBalancer URL (Port 80)
   - *Login*: `admin` / `prom-operator`
   - View Cluster Metrics, Node usage.

2. **Application**: Access via Ingress LoadBalancer URL (Port 80)
   - Verify Frontend accessible.
   - Verify Backend connectivity.

3. **SonarQube**: `http://<MGMT_SERVER_IP>:9000`
   - View code quality reports.

4. **ArgoCD**: `http://<ARGOCD_SERVER_LB>`
   - View application sync status.

---

## ✅ Production Readiness Checklist

- [x] **IaC**: Infrastructure fully defined in Terraform.
- [x] **CaC**: Configuration fully defined in Ansible.
- [x] **Security**:
  - No SSH Keys stored manually (Auto-generated).
  - No Open Ports (SSM used).
  - Private EKS Nodes.
  - Image Scanning (Trivy).
  - Code Analysis (SonarQube).
- [x] **Scalability**:
  - Separate Agent for builds.
  - EKS for Application.
- [x] **Observability**:
  - Full Prometheus/Grafana stack included.

This automation transforms the manual learning process into a robust, repeatable, enterprise-grade deployment strategy.
