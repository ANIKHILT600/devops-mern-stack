# DevSecOps Automation Implementation Guide

> **Goal:** Zero-click application deployment after every code push.
> **Context:** You have already completed the manual implementation. This guide automates the same steps using Terraform, Ansible, and Jenkins.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [File Map — What Does What](#file-map--what-does-what)
- [Phase 0 — Prerequisites (Local Machine)](#phase-0--prerequisites-local-machine)
- [Phase 1 — Bootstrap Terraform State Backend](#phase-1--bootstrap-terraform-state-backend)
- [Phase 2 — Provision Infrastructure (terraform apply)](#phase-2--provision-infrastructure-terraform-apply)
- [Phase 3 — Verify infra-mgmt Server](#phase-3--verify-infra-mgmt-server)
- [Phase 4 — Install Jenkins via Ansible](#phase-4--install-jenkins-via-ansible)
- [Phase 5 — Configure Jenkins (UI)](#phase-5--configure-jenkins-ui)
- [Phase 6 — Create Jenkins Jobs](#phase-6--create-jenkins-jobs)
- [Phase 7 — Pre-Steps Before Running App Pipelines](#phase-7--pre-steps-before-running-app-pipelines)
- [Phase 8 — Run Application Pipelines](#phase-8--run-application-pipelines)
- [Phase 9 — Access Your Application](#phase-9--access-your-application)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Management VPC (10.0.0.0/16)                               │
│  ┌─────────────────────┐  ┌──────────────────────────────┐  │
│  │  Jenkins Server      │  │  infra-mgmt-server           │  │
│  │  - Jenkins (8080)    │  │  - Jenkins Agent (label:     │  │
│  │  - Java 17           │  │    infra-mgmt)               │  │
│  │                      │  │  - Terraform, Ansible        │  │
│  └─────────────────────┘  │  - Docker, Trivy             │  │
│  (Ansible to Jenkins)     │  - SonarQube (port 9000)     │  │
│                            │  - AWS CLI v2                │  │
│                            └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Production VPC (192.168.0.0/16)                            │
│  ┌─────────────────────┐  ┌──────────────────────────────┐  │
│  │  Jump Server         │  │  EKS Cluster (Private        │  │
│  │  - kubectl, eksctl   │  │  Subnets)                    │  │
│  │  - helm, aws cli     │  │  - ArgoCD                    │  │
│  │  (gateway to EKS)    │  │  - Prometheus + Grafana      │  │
│  └─────────────────────┘  │  - App: database, backend,   │  │
│                            │    frontend (via ArgoCD)     │  │
│                            └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Tool Roles

| Component | Role | Where it Runs |
|-----------|------|---------------|
| Terraform | Creates VPCs, EC2s, EKS, ECR, IAM | Local / infra-mgmt |
| Ansible (`jenkins.yml`) | Installs Jenkins + auto-configures all credentials | Runs on infra-mgmt, targets Jenkins server |
| Ansible (`mgmt_server.yml`) | Installs tools on infra-mgmt (redundant with userdata) | Runs on infra-mgmt, targets itself |
| Ansible (`jump_server.yml`) | Installs kubectl/helm/eksctl/awscli on Jump Server | Runs on infra-mgmt, targets jump server |
| Ansible (`eks.yml`) | Deploys LB Controller, ArgoCD, Prometheus, ArgoCD apps | Runs on jump server |
| `Jenkinsfile.infra` | **Pipeline:** Terraform + all Ansible | infra-mgmt agent |
| `Jenkinsfile-Backend` | **Pipeline:** Build → Push ECR → Update K8s tag | infra-mgmt agent |
| `Jenkinsfile-Frontend` | **Pipeline:** Build → Push ECR → Update K8s tag | infra-mgmt agent |
| ArgoCD | Watches `K8s-Manifests/`, auto-deploys to EKS | In-cluster |

### CI/CD Flow (After Setup)

```
Developer pushes code
       ↓
Jenkins App-Deploy-Backend (or Frontend) pipeline triggered
       ↓
[SonarQube scan] → [Trivy fs scan] → [Docker build] → [ECR push]
       ↓
[Trivy image scan] → [Update deployment.yaml tag] → [git push]
       ↓
ArgoCD detects Git change → Syncs K8s-Manifests → Redeploys pod
```

---

## File Map — What Does What

```
automation/
├── terraform/
│   ├── main.tf               ← Provisions ALL infra (VPCs, EC2s, EKS, ECR, IAM, SSM endpoints)
│   ├── backend.tf            ← S3 remote state + DynamoDB lock
│   ├── variables.tf          ← All configurable variables
│   ├── terraform.tfvars      ← Your overrides (instance types, etc.)
│   ├── outputs.tf            ← IP addresses, EKS endpoint, ECR URLs
│   ├── inventory.tpl         ← Template → generates ansible/inventory.ini
│   └── modules/
│       ├── vpc/              ← VPC, subnets, IGW, NAT, route tables
│       ├── ec2_generic/      ← Generic EC2 (used for all 3 servers)
│       ├── security_groups_mgmt/  ← SGs for Management VPC
│       ├── security_groups_eks/   ← SGs for Production VPC
│       ├── eks/              ← EKS cluster + node group
│       ├── ecr/              ← ECR repositories
│       └── iam/              ← IAM roles for all resources
│
├── ansible/
│   ├── ansible.cfg           ← Ansible global settings
│   ├── inventory.ini         ← AUTO-GENERATED by terraform apply
│   ├── private_key.pem       ← AUTO-GENERATED by terraform apply
│   ├── group_vars/all.yml    ← Variables (secrets via --extra-vars)
│   ├── jenkins.yml           ← Installs Jenkins + all credentials + agent node
│   ├── mgmt_server.yml       ← Configures infra-mgmt (Terraform/Ansible/Docker/Trivy)
│   ├── jump_server.yml       ← Configures jump server (kubectl/helm/eksctl)
│   └── eks.yml               ← Deploys LB Controller, ArgoCD, Prometheus, apps
│
├── jenkins/
│   ├── Jenkinsfile.infra     ← Pipeline: Terraform + Ansible (all-in-one infra)
│   ├── Jenkinsfile.config    ← Pipeline: Ansible-only (reconfigure without Terraform)
│   └── Jenkinsfile.master    ← Pipeline: Orchestrator (calls all other pipelines)
│
└── k8s/
    └── argocd-apps.yaml      ← ArgoCD Application CRDs for database/backend/frontend/ingress

Jenkins-Pipeline-Script/      ← CANONICAL app pipeline files
├── Jenkinsfile-Backend        ← Build + scan + push + update K8s tag (backend)
└── Jenkinsfile-Frontend       ← Build + scan + push + update K8s tag (frontend)

K8s-Manifests/                ← ArgoCD watches these directories
├── Database/                  ← MongoDB: deployment, service, secret, pv, pvc
├── Backend/                   ← API: deployment (image tag updated by Jenkins), service
├── Frontend/                  ← React: deployment (image tag updated by Jenkins), service
└── ingress/                   ← AWS ALB Ingress (update host: to your domain)
    └── ingress.yaml
```

---

## Phase 0 — Prerequisites (Local Machine)

**Why:** Everything runs from your local machine first. You need these tools installed.

```bash
# Verify all required tools are installed:
aws --version                  # aws-cli/2.x.x
terraform --version             # Terraform v1.5+
git --version                   # git 2.x
```

**Configure AWS credentials:**
```bash
aws configure
# AWS Access Key ID:     <your-key>
# AWS Secret Access Key: <your-secret>
# Default region:         us-east-1
# Output format:          json

# Verify:
aws sts get-caller-identity
# → should show your Account ID
```

**Clone the repository (if not already done):**
```bash
git clone https://github.com/ANIKHILT600/devops-mern-stack.git
cd devops-mern-stack
```

---

## Phase 1 — Bootstrap Terraform State Backend

**Why:** Terraform state must be stored in S3 (not locally) so that both your local machine AND the infra-mgmt Jenkins agent share the same state. DynamoDB prevents concurrent runs from corrupting state.

**Run ONCE from your local machine:**

```bash
# Replace YOUR_ACCOUNT_ID with your actual 12-digit AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# 1. Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket "three-tier-app-tfstate-${ACCOUNT_ID}" \
  --region us-east-1

# Can verify using "aws s3 ls"

# 2. Enable versioning (allows rollback to previous state)
aws s3api put-bucket-versioning \
  --bucket "three-tier-app-tfstate-${ACCOUNT_ID}" \
  --versioning-configuration Status=Enabled

# 3. Enable encryption
aws s3api put-bucket-encryption \
  --bucket "three-tier-app-tfstate-${ACCOUNT_ID}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 4. Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name three-tier-app-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

echo "✅ State backend ready: three-tier-app-tfstate-${ACCOUNT_ID}"
```

**Update `automation/terraform/backend.tf`:**
```hcl
# Find this line and update:
bucket = "three-tier-app-tfstate-REPLACE_WITH_ACCOUNT_ID"
# Change to (example):
bucket = "three-tier-app-tfstate-123456789012"
```

---

## Phase 2 — Provision Infrastructure (terraform apply)

**Why:** Creates 2 VPCs, 3 EC2 servers (Jenkins, infra-mgmt, jump), EKS cluster, ECR repositories, IAM roles, and SSM endpoints. Also auto-generates `inventory.ini` and `private_key.pem` in `automation/ansible/`.

**From your local machine:**

```bash
cd automation/terraform

# Initialize Terraform (downloads providers, connects to S3 backend)
terraform init

# Preview what will be created
terraform plan

# Create all infrastructure (~25-35 minutes for EKS)
terraform apply
# Type 'yes' when prompted
```

**Expected outputs after apply:**
```
infra_mgmt_server_ip   = "3.x.x.x"
jenkins_server_ip      = "54.x.x.x"
jump_server_ip         = "52.x.x.x"
eks_cluster_name       = "three-tier-cluster"
ecr_frontend_url       = "<account>.dkr.ecr.us-east-1.amazonaws.com/frontend"
ecr_backend_url        = "<account>.dkr.ecr.us-east-1.amazonaws.com/backend"
```

### Step 2.1 — Update K8s-Manifests ECR Account ID

> ⚠️ **CRITICAL — Do this NOW before running any pipelines.**
>
> `K8s-Manifests/Backend/deployment.yaml` and `K8s-Manifests/Frontend/deployment.yaml`
> contain a hardcoded old account ID (`748787803760`). Replace it with YOUR account ID.
> If you skip this, ArgoCD will try to pull images from the wrong AWS account and fail.

```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update Backend deployment
sed -i "s/748787803760/${ACCOUNT_ID}/g" K8s-Manifests/Backend/deployment.yaml

# Update Frontend deployment
sed -i "s/748787803760/${ACCOUNT_ID}/g" K8s-Manifests/Frontend/deployment.yaml

# Commit and push
git add K8s-Manifests/Backend/deployment.yaml K8s-Manifests/Frontend/deployment.yaml
git commit -m "fix: replace hardcoded account ID with actual account ID"
git push origin main
```

**Verify the update:**
```bash
grep "image:" K8s-Manifests/Backend/deployment.yaml
# Should show: <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/backend:1
grep "image:" K8s-Manifests/Frontend/deployment.yaml
# Should show: <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/frontend:1
```

### Step 2.2 — Push Generated Files to GitHub

**Why:** The infra-mgmt server later clones this repo to run Ansible. It needs `inventory.ini` and `private_key.pem` with the real server IPs. These files are generated by `terraform apply` into `automation/ansible/`.

```bash
# From repo root (back out from automation/terraform)
cd ../..

# Stage the generated files — note --force required because these files
# are listed in .gitignore (sensitive generated files, see .gitignore comments)
git add --force automation/ansible/inventory.ini
git add --force automation/ansible/private_key.pem

git commit -m "ci: add terraform-generated inventory and SSH key [skip ci]"
git push origin main
```

**Verify `inventory.ini` has real IPs:**
```bash
cat automation/ansible/inventory.ini
# Should show actual IP addresses, NOT placeholder text
```

---

## Phase 3 — Verify infra-mgmt Server

**Why:** The infra-mgmt server installs all DevSecOps tools via EC2 userdata at boot time. It takes ~10 minutes to complete. You must verify it's ready before running Ansible.

**Access via AWS SSM Session Manager (no SSH key needed):**
```bash
# Get instance ID
MGMT_ID=$(cd automation/terraform && terraform output -raw infra_mgmt_instance_id)
echo "Mgmt Instance ID: $MGMT_ID"

# Open SSM session
aws ssm start-session --target $MGMT_ID
```

**Inside the SSM session:**
```bash
sudo -i   # become root

# Verify all tools are installed via terraform ec2-userdata
terraform --version         # Terraform 1.x.x
ansible --version           # ansible 2.x.x
docker --version            # Docker 2x.x.x
trivy --version             # Version: x.x.x
aws --version               # aws-cli/2.x.x
java --version              # openjdk 17.x.x
ls /home/ubuntu/jenkins_agent/   # Directory exists
# Verify SonarQube is running
docker ps | grep sonar
# Should show: sonar  sonarqube:lts-community  Up x minutes  0.0.0.0:9000->9000/tcp
```

- **Outcome:** All tools confirmed ready. infra-mgmt is a fully capable DevSecOps server.

---

## Phase 4 — Install Jenkins via Ansible

**Why:** Jenkins must be installed on the Jenkins Server. This is done MANUALLY once via Ansible from the infra-mgmt server. After Jenkins is running, all future runs go through Jenkins pipelines.

**Still inside the SSM session on infra-mgmt:**

```bash
sudo -i

# Clone the repo (this gets the generated inventory.ini + private_key.pem you pushed)
cd ~

git clone https://github.com/ANIKHILT600/devops-mern-stack.git

cd devops-mern-stack/automation/ansible

# Activate venv (so boto3 is available to Ansible AWS modules. Note we have installed ansible in devops-venv in side infr-mngmt-server)
source /opt/devops-venv/bin/activate

# Fix private key permissions (required for SSH)
chmod 400 private_key.pem

# Test SSH connectivity to Jenkins server
ansible jenkins_server -i inventory.ini -m ping
# Expected: "pong" — if this fails, check security groups allow port 22

> **Getting your GitHub PAT:** GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic) → Generate new. Scopes: `repo`, `workflow`.

> **Getting your SonarQube token:** After first accessing SonarQube UI (`http://<mgmt_ip>:9000`), log in as admin/admin (forced to change), go to My Account → Security → Generate Token. Use that token here.

# Run Jenkins playbook (~10 minutes)
ansible-playbook -i inventory.ini jenkins.yml \
  --extra-vars "sonar_token=CHANGE_ME \
                github_token=YOUR_GITHUB_PAT \
                github_username=ANIKHILT600 \
                aws_account_id=$(aws sts get-caller-identity --query Account --output text)" -v
```

**Outcome:** Jenkins installed on Jenkins Server. Admin user + all credentials + infra-mgmt agent node configured automatically via Groovy init scripts.

### Post-Install Verification

| Check | Where | Expected |
|-------|-------|----------|
| Jenkins UI accessible | `http://<jenkins_ip>:8080` | Login page |
| Admin login | admin / admin_password_changed_later | Dashboard |
| **Change password** | User icon → Configure → Password | Done |
| Agent node online | Manage Jenkins → Nodes → infra-mgmt | 🟢 Green |
| Credentials created | Manage Jenkins → Credentials → Global | 8 credentials |

**Expected credentials:** `sonar-token`, `GITHUB`, `github`, `AWS_ACCOUNT_ID`, `ECR_REPO_FRONTEND`, `ECR_REPO_BACKEND`, `infra-ssh-key`

---

## Phase 5 — Jenkins Auto-Configuration (Via Ansible)

**Status: FULLY AUTOMATED ✅**

The previous manual configuration steps (adding credentials, SonarQube server, tools, etc.) are now **automatically handled** by the Ansible `jenkins.yml` playbook through Groovy init scripts.

### What Gets Automated

**Phase 4 (Post Ansible Execution) — Jenkins init.groovy.d scripts run automatically:**

| Component | Automation | Verification |
|-----------|-----------|---|
| **Credentials (7 total)** | Created via `02-credentials.groovy` | Jenkins UI → Manage Jenkins → Credentials |
| **SonarQube Server** | Configured via `03-sonarqube-server.groovy` | Jenkins UI → Manage Jenkins → Configure System → SonarQube Servers |
| **NodeJS Tool** | Configured via `04-tools-configuration.groovy` | Jenkins UI → Manage Jenkins → Global Tool Configuration → NodeJS |
| **SonarQube Scanner** | Configured via `04-tools-configuration.groovy` | Jenkins UI → Manage Jenkins → Global Tool Configuration → SonarQube Scanner |
| **Agent Node (infra-mgmt)** | Configured via `05-agent-node.groovy` | Jenkins UI → Manage Jenkins → Nodes and Clouds |
| **Pipeline Jobs (5 total)** | Created via Jenkins CLI | Jenkins UI → Dashboard → Job list |

### Credentials Automatically Created

```
✓ infra-ssh-key          SSH key for Jenkins agents
✓ sonar-token            SonarQube authentication token
✓ GITHUB                 GitHub username/password (for git checkout)
✓ github                 GitHub PAT (for git push in pipelines)
✓ AWS_ACCOUNT_ID         AWS account ID for ECR operations
✓ ECR_REPO_FRONTEND      Frontend ECR repository name
✓ ECR_REPO_BACKEND       Backend ECR repository name
```

### SonarQube Server Auto-Configuration

```
Name:       sonar-server
Server URL: http://<infra_mgmt_PRIVATE_ip>:9000
Auth Token: sonar-token (auto-linked)
Auto-Save:  ✓ Enabled
```

### Tools Auto-Configuration

**NodeJS:**
```
Name:    nodejs
Version: auto (latest LTS auto-downloaded)
```

**SonarQube Scanner:**
```
Name:    sonar-scanner
Version: auto (latest auto-downloaded)
```

### Verification After Ansible Playbook Completion

```bash
# 1. Check credentials are present
Jenkins UI → Manage Jenkins → Credentials → Global
# Should see all 7 credentials listed

# 2. Verify SonarQube server configuration
Jenkins UI → Manage Jenkins → Configure System → SonarQube Servers
# Should show: sonar-server (http://<ip>:9000)

# 3. Verify tools are configured
Jenkins UI → Manage Jenkins → Global Tool Configuration
# Should show: nodejs and sonar-scanner with auto-download enabled

# 4. Verify agent node is online
Jenkins UI → Manage Jenkins → Nodes and Clouds
# Should show: infra-mgmt node with status 🟢 Online

# 5. Verify pipeline jobs are created
Jenkins UI → Dashboard
# Should show: 5 pipeline jobs (Infra-Provisioning, Config-Only, App-Deploy-Backend/Frontend, DevSecOps-Master)
```

### Manual Verification Only (No Configuration Needed)

If any component is missing after Ansible completes, you can manually verify using the Jenkins UI. The Groovy scripts include error handling and will skip if components already exist.

**Common Check:** In Jenkins → Manage Jenkins → Configure System, search for "SonarQube Servers" to confirm auto-configuration worked.

---

## Phase 6 — Jenkins Pipeline Jobs (Auto-Created)

**Status: FULLY AUTOMATED ✅**

Jenkins pipeline jobs are automatically created during the Ansible `jenkins.yml` playbook execution. You no longer need to create them manually via the Jenkins UI.

### What Gets Auto-Created

The Ansible playbook creates 5 pipeline jobs:

| Job Name | Jenkinsfile Path | Purpose |
|----------|------------------|---------|
| **Infra-Provisioning** | `automation/jenkins/Jenkinsfile.infra` | Terraform + all Ansible playbooks (initial infrastructure) |
| **Config-Only** | `automation/jenkins/Jenkinsfile.config` | Re-run Ansible only (without Terraform) |
| **App-Deploy-Backend** | `Jenkins-Pipeline-Script/Jenkinsfile-Backend` | Backend CI/CD pipeline (build, scan, push, deploy) |
| **App-Deploy-Frontend** | `Jenkins-Pipeline-Script/Jenkinsfile-Frontend` | Frontend CI/CD pipeline (build, scan, push, deploy) |
| **DevSecOps-Master** | `automation/jenkins/Jenkinsfile.master` | Master orchestrator pipeline (optional) |

### Verification (Optional Manual Verification Only)

```bash
# Check all jobs are created
Jenkins UI → Dashboard
# Should show: 5 pipeline jobs listed in the main dashboard
```

### To Run a Pipeline Job

```
Jenkins UI → <Job Name> → Build Now
```

Example:
```
Jenkins UI → Infra-Provisioning → Build Now
```

---

## ⚠️ Migration Note: Manual → Automated Configuration

**Old Approach (Phase 5.1-5.4 — DEPRECATED):**
- Manually add credentials via Jenkins UI
- Manually configure SonarQube server
- Manually add NodeJS tool  - Manually add SonarQube Scanner tool
- Manually create 5 pipeline jobs

**New Approach (Fully Automated via Ansible):**
- All 7 credentials created automatically
- SonarQube server configured automatically
- NodeJS tool configured automatically
- SonarQube Scanner tool configured automatically
- Agent node (infra-mgmt) configured automatically
- All 5 pipeline jobs created automatically

**When Running Ansible Playbook:**
```bash
ansible-playbook -i inventory.ini jenkins.yml \
  --extra-vars "sonar_token=YOUR_TOKEN \
                github_token=YOUR_PAT \
                github_username=YOUR_USERNAME \
                aws_account_id=YOUR_ACCOUNT_ID \
                infra_mgmt_private_ip=<IP from terraform outputs>"
```

All configuration is complete after Ansible finishes!

---

## Phase 7 — Pre-Steps Before Running App Pipelines

### Step 7.1 — Run Infra-Provisioning Pipeline (Jump Server + EKS Setup)

**Why:** This pipeline runs `jump_server.yml` and `eks.yml` Ansible playbooks that install kubectl/helm on the jump server and deploy ArgoCD, Prometheus, and ArgoCD app definitions into EKS.

```
Jenkins UI → Infra-Provisioning → Build with Parameters
  TERRAFORM_ACTION: apply    ← Terraform sees "no changes" (infra already exists)
  AUTO_APPROVE:     false
  AWS_REGION:       us-east-1
→ Build
```

**Pipeline stages:**

| Stage | What Happens |
|-------|-------------|
| Pre-Flight | Prints parameters |
| Git Checkout | Pulls latest code |
| Tool Validation | Verifies terraform, ansible, aws, docker, trivy |
| Terraform Init | Connects to S3 backend |
| Terraform Plan | Shows "No changes" (infra exists) |
| Terraform Apply | Skipped (no changes) |
| Capture Outputs | Reads IP addresses from state |
| **Ansible Config** | Runs 4 playbooks: mgmt_server → jenkins → jump_server → **eks** |
| Validation | Prints success |

- **Outcome:** Jump server has kubectl/eksctl/helm. EKS has ArgoCD, Prometheus+Grafana, AWS LB Controller. ArgoCD app CRDs deployed, watching K8s-Manifests/.

### Step 7.2 — Verify ArgoCD Applications

```bash
# From jump server (via SSM session)
aws ssm start-session --target <jump_server_instance_id>

# Inside jump server:
kubectl get applications -n argocd
```

Expected:
```
NAME       SYNC STATUS   HEALTH STATUS
database   Synced        Healthy
backend    Synced        Healthy (or Degraded until image built)
frontend   Synced        Healthy (or Degraded until image built)
ingress    Synced        Healthy
```

> ⚠️ `backend` and `frontend` will show **Degraded** until you run the app pipelines (they need the Docker image to be built and pushed to ECR first).

### Step 7.3 — Update ingress.yaml with Your Domain

`K8s-Manifests/ingress/ingress.yaml` currently has `host: tarangan4u.dpdns.org`. Update it with YOUR domain:

```bash
# Option A: Use a domain you own
sed -i "s/tarangan4u.dpdns.org/yourdomain.com/" K8s-Manifests/ingress/ingress.yaml

# Option B: Remove the host: line entirely (makes it a wildcard — accepts any host)
# Edit the file: delete line 13 (- host: tarangan4u.dpdns.org) and the http: indent
```

Also update the frontend's `REACT_APP_BACKEND_URL` environment variable in `K8s-Manifests/Frontend/deployment.yaml` to use your domain:
```yaml
- name: REACT_APP_BACKEND_URL
  value: "http://yourdomain.com/api/tasks"   # ← Update to your domain
```

Commit and push:
```bash
git add K8s-Manifests/ingress/ingress.yaml K8s-Manifests/Frontend/deployment.yaml
git commit -m "config: update domain to production URL"
git push origin main
```

---

## Phase 8 — Run Application Pipelines

### Step 8.1 — Run App-Deploy-Backend

```
Jenkins UI → App-Deploy-Backend → Build Now
```

**What happens:**
1. **Checkout** → Clones repo (gets `Application-Code/backend/` + `K8s-Manifests/Backend/`)
2. **SonarQube Analysis** → Scans `Application-Code/backend/` → Sends to SonarQube
3. **Quality Gate** → Waits for SonarQube quality check (abortPipeline=false, won't fail build)
4. **Trivy File Scan** → Scans filesystem for CVEs → `trivyfs.txt`
5. **Docker Build** → `docker build -t backend Application-Code/backend/`
6. **ECR Push** → Tags as `:${BUILD_NUMBER}`, pushes to `<account>.dkr.ecr.us-east-1.amazonaws.com/backend:${BUILD_NUMBER}`
7. **Trivy Image Scan** → Scans Docker image for CVEs → `trivyimage.txt`
8. **Update Deployment** → Opens `K8s-Manifests/Backend/deployment.yaml`, replaces `backend:1` with `backend:${BUILD_NUMBER}`, commits and pushes to GitHub
9. **ArgoCD detects** the git push → Syncs → Pulls new image from ECR → Redeploys pod

### Step 8.2 — Run App-Deploy-Frontend

```
Jenkins UI → App-Deploy-Frontend → Build Now
```

Same flow as backend, operating on `Application-Code/frontend/` and `K8s-Manifests/Frontend/`.

---

## Phase 9 — Access Your Application

### Get ArgoCD URL

```bash
# Inside jump server SSM session:
kubectl get svc -n argocd argocd-server
```

ArgoCD URL: `http://<EXTERNAL-IP>` (the LoadBalancer external hostname)

**ArgoCD credentials:**
```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Get Application URL

```bash
# Check ALB ingress hostname
kubectl get ingress -n three-tier
```

The `ADDRESS` column shows your ALB hostname (e.g., `k8s-threetie-mainlb-xxxx.us-east-1.elb.amazonaws.com`)

If you configured a domain, create a CNAME DNS record:
```
yourdomain.com → k8s-threetie-mainlb-xxxx.us-east-1.elb.amazonaws.com
```

### Get Grafana URL

```bash
kubectl get svc -n prometheus prometheus-grafana
```

**Grafana credentials:** `admin` / `prom-operator`

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `terraform init` fails: "bucket not found" | S3 bucket not created or wrong name in backend.tf | Run Phase 1 commands, update bucket name in backend.tf |
| `ansible jenkins_server -m ping` fails | SSH port 22 blocked or wrong key permissions | Check security group inbound port 22; `chmod 400 private_key.pem` |
| Jenkins UI not accessible | Jenkins install failed or port 8080 blocked | SSM to Jenkins server: `systemctl status jenkins`, check SG |
| Agent node shows "offline" | SSH from Jenkins to infra-mgmt failed | Manage Jenkins → Nodes → infra-mgmt → Launch agent, check SSH key |
| `withSonarQubeEnv('sonar-server')` fails | SonarQube server name not configured | Jenkins → Configure System → SonarQube Servers → Name must be `sonar-server` |
| `ECR_REPO_BACKEND` credential error | Credential ID mismatch in jenkins.yml | Confirm jenkins.yml Groovy creates `ECR_REPO_BACKEND` with value `backend` |
| `docker: command not found` in pipeline | Pipeline running on Jenkins master (not infra-mgmt agent) | Jenkinsfiles must use `agent { label 'infra-mgmt' }` — verify agent is online |
| ArgoCD `backend` app Degraded | Image not in ECR yet | Run App-Deploy-Backend pipeline first |
| ArgoCD `ingress` app Missing/Failed | `K8s-Manifests/ingress/` directory didn't exist | Already fixed: directory + ingress.yaml created |
| `sed` doesn't update deployment.yaml | ECR repo name mismatch | `ECR_REPO_BACKEND` credential value must match image name in deployment.yaml (should be `backend`) |
| Jenkins pipeline: `backend:1/backend:1` (same tag) | BUILD_NUMBER=1 and image already at :1 | Run pipeline again — next build number will be 2 |
| EKS nodes not joining | IAM node role missing policies | Check IAM: node role needs AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly |
| `eksctl create iamserviceaccount` fails | OIDC not associated | `eksctl utils associate-iam-oidc-provider --region=us-east-1 --cluster=three-tier-cluster --approve` |
| Prometheus/Grafana pods Pending | Insufficient EKS node resources | Nodes need at least m7i-flex.large (3 nodes) |

---

## Key Variables to Know

| Variable | File | Default | Notes |
|----------|------|---------|-------|
| ECR repo names | `variables.tf` | `["frontend","backend"]` | Must match deployment.yaml image names |
| Cluster name | `variables.tf` | `three-tier-cluster` | Used in AWS CLI commands |
| State bucket | `backend.tf` | `REPLACE_WITH_ACCOUNT_ID` | **Must update before terraform init** |
| Jenkins admin password | `group_vars/all.yml` | `admin_password_changed_later` | Change in Jenkins UI after setup |
| SonarQube server name | `jenkins.yml` (Groovy) | `sonar-server` | Must match `withSonarQubeEnv('sonar-server')` in Jenkinsfiles |
| Jenkins agent label | `jenkins.yml` (Groovy) | `infra-mgmt` | Must match `agent { label 'infra-mgmt' }` in Jenkinsfiles |
| ArgoCD version | `group_vars/all.yml` | `v2.4.7` | Update if needed |
| Grafana password | `eks.yml` | `prom-operator` | Change after first login |
