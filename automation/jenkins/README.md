# Jenkins Pipeline Files

This directory contains all Jenkins pipeline definitions for the DevSecOps automation.

## 📁 Pipeline Files

### 1. `Jenkinsfile.master`
**Master Orchestration Pipeline**

- Triggers infrastructure provisioning
- Then triggers application deployments (Backend & Frontend in parallel)
- Provides overall deployment status

**Usage**: Run this for complete end-to-end automation

---

### 2. `Jenkinsfile.infra`
**Infrastructure Provisioning Pipeline**

**Stages**:
1. ✓ Pre-Flight Checks
2. ✓ Git Checkout
3. ✓ Tool Installation & Validation
4. ✓ Tool Configuration
5. ✓ Terraform Initialization
6. ✓ Terraform Plan
7. ✓ Terraform Apply/Destroy
8. ✓ Capture Infrastructure Outputs
9. ✓ Ansible Configuration
10. ✓ Infrastructure Validation

**Parameters**:
- `TERRAFORM_ACTION`: apply | plan | destroy
- `AUTO_APPROVE`: true | false
- `AWS_REGION`: us-east-1 (default)

**Duration**: ~30-40 minutes (for apply)

---

### 3. `Jenkinsfile.backend`
**Backend Application Deployment Pipeline**

**Stages**:
1. 🧹 Cleaning Workspace
2. 📥 Checkout from Git
3. 🔍 SonarQube Analysis
4. 🎯 Quality Gate Check
5. 🔒 Trivy File System Scan
6. 🐳 Docker Image Build
7. 📤 ECR Image Pushing
8. 🔐 Trivy Image Scan
9. 📝 Update Kubernetes Deployment Manifest
10. ✅ Deployment Summary

**Environment Variables**:
- `AWS_ECR_REPO_NAME`: three-tier-backend
- `SONAR_PROJECT_KEY`: backend
- `APP_DIR`: Application-Code/backend
- `K8S_MANIFEST_DIR`: K8s-Manifests/Backend

**Duration**: ~10-15 minutes

---

### 4. `Jenkinsfile.frontend`
**Frontend Application Deployment Pipeline**

**Stages**: (Same as Backend)
1. 🧹 Cleaning Workspace
2. 📥 Checkout from Git
3. 🔍 SonarQube Analysis
4. 🎯 Quality Gate Check
5. 🔒 Trivy File System Scan
6. 🐳 Docker Image Build
7. 📤 ECR Image Pushing
8. 🔐 Trivy Image Scan
9. 📝 Update Kubernetes Deployment Manifest
10. ✅ Deployment Summary

**Environment Variables**:
- `AWS_ECR_REPO_NAME`: three-tier-frontend
- `SONAR_PROJECT_KEY`: frontend
- `APP_DIR`: Application-Code/frontend
- `K8S_MANIFEST_DIR`: K8s-Manifests/Frontend

**Duration**: ~10-15 minutes

---

## 🚀 Quick Start

### First Time Setup

1. **Configure Jenkins** (See [JENKINS_PIPELINE_SETUP.md](../JENKINS_PIPELINE_SETUP.md))
   - Add Infra Mgmt Server as agent
   - Configure credentials
   - Install required plugins

2. **Create Pipeline Jobs**:
   ```
   - DevSecOps-Master-Pipeline → Jenkinsfile.master
   - Infra-Provisioning → Jenkinsfile.infra
   - App-Deploy-Backend → Jenkinsfile.backend
   - App-Deploy-Frontend → Jenkinsfile.frontend
   ```

3. **Run Master Pipeline**:
   - Automatically provisions infrastructure
   - Deploys both applications
   - Complete automation!

---

## 🔄 Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│                 DevSecOps-Master-Pipeline                   │
│                   (Jenkinsfile.master)                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
        ┌────────────────────────────────────┐
        │      Infra-Provisioning            │
        │     (Jenkinsfile.infra)            │
        │  • Terraform Init/Plan/Apply       │
        │  • Ansible Configuration           │
        └────────────────┬───────────────────┘
                         │
                         ▼
        ┌────────────────────────────────────┐
        │   Application Deployment (Parallel)│
        ├────────────────┬───────────────────┤
        │                │                   │
        ▼                ▼                   │
┌──────────────┐  ┌──────────────┐         │
│   Backend    │  │   Frontend   │         │
│  Deployment  │  │  Deployment  │         │
│              │  │              │         │
│ • SonarQube  │  │ • SonarQube  │         │
│ • Trivy Scan │  │ • Trivy Scan │         │
│ • Docker     │  │ • Docker     │         │
│ • ECR Push   │  │ • ECR Push   │         │
│ • K8s Update │  │ • K8s Update │         │
└──────────────┘  └──────────────┘         │
        │                │                   │
        └────────────────┴───────────────────┘
                         │
                         ▼
                    ✅ Complete!
```

---

## 📋 Required Jenkins Credentials

| Credential ID | Type | Description |
|--------------|------|-------------|
| `aws_creds` | AWS Credentials | AWS Access Key & Secret |
| `AWS_ACCOUNT_ID` | Secret Text | 12-digit AWS Account ID |
| `github` | Secret Text | GitHub Personal Access Token |
| `GITHUB` | Username/Password | GitHub Credentials |
| `sonar-token` | Secret Text | SonarQube Token |
| `ECR_REPO_BACKEND` | Secret Text | Backend ECR repo name |
| `ECR_REPO_FRONTEND` | Secret Text | Frontend ECR repo name |

---

## 🛠️ Required Jenkins Tools

| Tool | Name | Version |
|------|------|---------|
| SonarQube Scanner | `sonar-scanner` | 4.8+ |
| Node.js | `nodejs` | 18.x or 20.x |

---

## 🎯 Pipeline Features

### Infrastructure Pipeline
- ✅ Parameterized (apply/plan/destroy)
- ✅ Tool validation before execution
- ✅ Terraform state management
- ✅ Ansible automation
- ✅ Output capture for downstream jobs

### Application Pipelines
- ✅ Code quality analysis (SonarQube)
- ✅ Security scanning (Trivy)
- ✅ Container image building
- ✅ ECR integration
- ✅ GitOps manifest updates
- ✅ Automated versioning (BUILD_NUMBER)

---

## 📊 Pipeline Outputs

### Infrastructure Pipeline
```
Infrastructure IPs:
  - Jenkins Server: <IP>
  - Mgmt Server: <IP>
  - Jump Server: <IP>
```

### Application Pipelines
```
Deployment Summary:
  - Build Number: <BUILD_NUMBER>
  - Image: <ECR_URI>:<TAG>
  - Status: Pushed & Manifest Updated
```

---

## 🐛 Troubleshooting

### Pipeline Fails at Tool Validation
**Solution**: Ensure Infra Mgmt Server has all tools installed
```bash
ssh ubuntu@<INFRA_MGMT_IP>
terraform --version
ansible --version
docker --version
trivy --version
```

### SonarQube Analysis Fails
**Solution**: Check SonarQube is running
```bash
docker ps | grep sonar
docker logs sonar
```

### ECR Push Fails
**Solution**: Verify AWS credentials and ECR permissions
```bash
aws ecr describe-repositories
```

### Manifest Update Fails
**Solution**: Check GitHub token permissions
- Token needs `repo` scope
- Branch protection rules may block pushes

---

## 📚 Documentation

- **Complete Setup Guide**: [JENKINS_PIPELINE_SETUP.md](../JENKINS_PIPELINE_SETUP.md)
- **Automation Overview**: [Automation_Implementation.md](../Automation_Implementation.md)
- **Manual Reference**: [Manual_Implementation.md](../../Manual_Implementation.md)

---

## 🔐 Security Notes

1. **Never commit credentials** to Git
2. **Use Jenkins credentials** for all secrets
3. **Rotate tokens** regularly
4. **Review Trivy scan results** before deployment
5. **Monitor SonarQube** quality gates

---

## 🎓 Best Practices

1. **Run Infra pipeline first** before app deployments
2. **Use parameters** for flexibility
3. **Monitor build logs** for issues
4. **Set up notifications** for failures
5. **Backup Jenkins config** regularly
6. **Use Blue Ocean** for better visualization

---

**Last Updated**: 2026-02-08  
**Version**: 1.0
