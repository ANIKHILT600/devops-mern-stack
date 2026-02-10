# End-to-End MERN Stack DevSecOps Project on AWS EKS : MANUAL IMPLEMENTATION (to learn basics)
This document is learning-grade but production-thinking. That is exactly what you want before automation.

## Table of Contents

- [Project Overview](./README.md#project-overview)
- [Prerequisites](./README.md#prerequisites)

- [Step 1: Install AWS CLI and IAM User Setup](#step-1-install-aws-cli-to-deploy-jenkins-serverec2-on-aws)
- [Step 2: Create Jenkins Server (EC2)](#step-2-create-jenkins-serverec2)
- [Step 3: Configure the Jenkins Server](#step-3-configure-the-jenkin-server)
- [Step 4: Deploy the EKS Cluster using eksctl](#step-4-deploy-the-eks-cluster-using-the-eksctl-commands)
- [Step 5: Create Jump Server](#step-5-create-jump-server)
- [Step 6: Validate EKS Cluster Connectivity](#step-6-validation-eks-cluster-connectivity)
- [Step 7: Configure AWS Load Balancer Controller](#step-7-configure-the-load-balancer-controller-on-eks-cluster)
- [Step 8: Configure SonarQube](#step-8-configure-sonarqube-for-our-devsecops-pipeline)
- [Step 9: Create Amazon ECR Private Repositories](#step-9-create-amazon-ecr-private-repositories-for-both-tiers-frontend--backend)
- [Step 10: Install Jenkins Plugins and Configure Credentials](#step-10-install-required-plugins-and-configure-credentials-in-jenkins)
- [Step 11: Build Jenkins Pipelines (Backend & Frontend)](#step-11-build-jenkin-pipelines-backend-frontend)
- [Step 12: Install and Configure ArgoCD](#step-12-install--configure-argocd)
- [Step 13: Deploy Three-Tier Application using ArgoCD](#step-13-deploy-our-three-tier-application-using-argocd)
- [Step 14: Configure DNS](#14-configure-dns)
- [Step 15: Monitoring with Prometheus and Grafana](#step-15-monitoring-with-prometheus--grafana)
- [Step 16: Validate Database Persistent Volume](#16-validation-database-persistent-volume)

- [Conclusion](#conclusion)


---

## Step 1: Install AWS CLI to deploy Jenkins Server(EC2) on AWS

Create an IAM user and generate AWS Access Keys.

1. Go to **AWS IAM → Users → Create user**
2. Provide a username → **Next**
3. Select **Attach policies directly**
4. Attach **AdministratorAccess** (for learning/testing only)
5. Create the user
6. Go to **Security Credentials → Create access key**
7. Select **CLI**, confirm, and create
8. Save the **Access Key & Secret Key** securely

Note: “In production, IAM roles attached to EC2 or CI systems should be used instead of long-lived access keys.”

On your local machine follow below and **install and configure AWS CLI:**

### Installing the AWS CLI
Download and install the AWS CLI on your local machine. You can find installation instructions for various operating systems [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html).

### Configure AWS CLI
From [step1](#step-1-iam-user-setup) get the access key and secret key. Open a terminal or command prompt and run the following command:

```bash
aws configure
```
Enter the access key ID and secret access key of the IAM user you created earlier. Choose a default region and output format for AWS CLI commands.

---

## Step 2: Create Jenkins Server(EC2)

Provision Jenkins EC2 instance with below configuration:

- Name: Jenkins-Server
- OS : Ubuntu 22.04
- Instance type : t2.2xlarge
- Security group : open inbound rule on 8080 and 9000
- Proceed without Key Pair
- IAM instance profile : create one IAM role for EC2 with administrator access (not recommended, just for demo)
- create

Use session manager connect after Jenkins EC2 instance creation.

Note: “Jenkins will be intentionally placed outside the EKS VPC to demonstrate private EKS endpoint behavior.”

---

## Step 3: Configure the Jenkin-server

On Jenkins-server(EC2) install below require tools:
```
sudo su ubuntu
```

**Intsalling Java**
```
sudo apt update -y

sudo apt install openjdk-17-jre -y

sudo apt install openjdk-17-jdk -y

java --version
```
**Installing Jenkins**
```
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update -y

sudo apt-get install jenkins -y
```

**Optional**:

*If you don't want to install Jenkins, you can create a container of Jenkins*
```
docker run -d -p 8080:8080 -p 50000:50000 --name jenkins-container jenkins/jenkins:lts

docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

But, jenkins container may not have trivy and docker cli to process the pipeline stages like (file scan docker image build). So can use Custom Jenkins Docker Image (Best practice):


1️⃣ Create a Dockerfile on the EC2(Jenkin-Server) host
```
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && \
    apt-get install -y wget gnupg lsb-release docker.io awscli && \
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
      | tee /usr/share/keyrings/trivy.gpg > /dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
      https://aquasecurity.github.io/trivy-repo/deb bookworm main" \
      | tee /etc/apt/sources.list.d/trivy.list && \
    apt-get update && \
    apt-get install -y trivy && \
    apt-get clean

USER jenkins
```

2️⃣ Build the custom Jenkins image
```
docker build -t jenkins-devsecops:lts .
```

3️⃣ Run Jenkins with Docker socket (IMPORTANT)
```
docker stop jenkins //if you are using jenkins image without trivy and/or docker cli, and already configure jenkins then
docker rm jenkins // remove if already using cotainer image
```
Run Jenkins with Docker socket:
```
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins-devsecops:lts
```

4️⃣ Verify inside container
```
docker exec -it jenkins trivy version
docker exec -it jenkins docker version
```
Your pipeline will now work. You did not lose Jenkins configuration because Jenkins data is stored in a persistent Docker volume(var/jenkins_home), not inside the Jenkins image/container.


**Installing Docker**
```
sudo apt install docker.io -y
```

Setup the installations:
```
sudo usermod -aG docker jenkins

sudo usermod -aG docker ubuntu

sudo systemctl restart docker

sudo chmod 777 /var/run/docker.sock
```

Note: “Granting 777 on docker.sock is insecure and used only for learning.”


**Install Sonarqube**

In production organizations, provision dedicated server for Sonarqube is recommended. But for this demo we will use same Jenkins-Server.

Run Docker Container of Sonarqube:
```
docker run -d  --name sonar -p 9000:9000 sonarqube:lts-community
```

**Installing AWS CLI**

```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

sudo apt install unzip -y

unzip awscliv2.zip

sudo ./aws/install
```

**Installing eksctl**
```
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin
```

**Installing Kubectl**
Actually kubectl is not require on Jenkins-Server, but will test some connectivity hence installing:

```
sudo apt install curl -y

sudo curl -LO "https://dl.k8s.io/release/v1.28.4/bin/linux/amd64/kubectl"

sudo chmod +x kubectl

sudo mv kubectl /usr/local/bin/

kubectl version --client
```


**Installing Trivy**

```
sudo apt-get install wget apt-transport-https gnupg lsb-release -y

wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -

echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list

sudo apt update

sudo apt install trivy -y
```

### Validate installed tools:

```bash
jenkins --version
docker --version
kubectl version
eksctl version
aws --version
trivy --version
```

Access Jenkins:

```
http://<Jenkin-Server_PUBLIC_IP>:8080
```
Run below command on server to get jenkins initial password:

```
systemctl status jenkins.service
```
or (recommended)
```
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Install suggested plugins and complete setup.

---

## Step 4: Deploy the EKS Cluster using the eksctl commands

The EKS cluster is created using the eksctl utility. If the EKS cluster created via eksctl, it always create vpc and runs inside a VPC:

```
eksctl create cluster --name Three-Tier-Cluster --region us-east-1 --node-type t2.medium --nodes-min 2 --nodes-max 2
```
```
aws eks update-kubeconfig --region us-east-1 --name Three-Tier-Cluster
```
```
kubectl get nodes
```


**Optional** If your cluster is failing due below you can utilize cluster-ec2.yaml to provision same:

EKS control plane creation succeeded, but managed node groups failed due to bootstrap and Auto Mode behavior. Disabling Auto Mode and using a stable Kubernetes version with explicit networking resolved the issue.
```
eksctl create cluster -f cluster-ec2.yaml
```

**Troubleshooting(optional)**
1. Check if your cluster is private or not. Check current endpoint configuration :

```
aws eks describe-cluster \
  --name Three-Tier-Cluster \
  --region us-east-1 \
  --query "cluster.resourcesVpcConfig"
```
2. If your public access is true, then do below to make it private:
```
aws eks update-cluster-config \
  --name Three-Tier-Cluster \
  --region us-east-1 \
  --resources-vpc-config \
  endpointPublicAccess=false,endpointPrivateAccess=true
```
3. Update and check kubeconfig:
```
aws eks update-kubeconfig --name Three-Tier-Cluster

kubectl get nodes
```


---


## Step 5: Create Jump-server

Provision Jump-Server EC2 instance with below configuration in same VPC's public subnet where eks cluster created (from step 4).

Note: You can navigate to AWS console and then EKS cluster to get vpc and public subnet (Route to Internet Gateway (igw-xxxx)).

Launch Jump-Server:

- Name: Jump-Server
- OS : Ubuntu 22.04
- Instance type : t2.medium
- Proceed without Key Pair
- IAM instance profile : create or use same from step2 IAM role for EC2 with administrator access (not recommended, just for demo)
- create

Use session manager connect after Jump-Server EC2 instance creation.

### Installation of required tools

**Installing AWS CLI**
```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

sudo apt install unzip -y

unzip awscliv2.zip

sudo ./aws/install
```

**Installing Kubectl**
```
sudo apt update

sudo apt install curl -y

sudo curl -LO "https://dl.k8s.io/release/v1.28.4/bin/linux/amd64/kubectl"

sudo chmod +x kubectl

sudo mv kubectl /usr/local/bin/

kubectl version --client
```

**Installing eksctl**
```
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin

eksctl version
```

**Intalling Helm**
```
sudo snap install helm --classic
```
### Validate installed tools:

```bash
kubectl version
eksctl version
aws --version
helm --version
```

## Step 6: Validation EKS Cluster connectivity

**1. Connectivity from Jenkin Server (different VPC)**

From Jenkin-Server (EC2), run below commands:

```
aws configure
```
and provide secret's from step 1

```
aws eks update-kubeconfig --name Three-Tier-Cluster

kubectl get nodes
```

**Result**: FAILED (expected and correct) with error "Couldn't get current server ......"

**Why it failed**: Jenkins server is in a different VPC and EKS API endpoint is private-only. Private endpoint is not routable across VPCs.


**2. Connectivity from Jump Server (inside EKS VPC)**

From Jump-Server (EC2), run below commands:

```
aws config
```
and provide secret's from step 1

```
aws eks update-kubeconfig --name Three-Tier-Cluster

kubectl get nodess
```

**Result**: SUCCESS

**Why it worked**: Jump server is in the same VPC as EKS. EKS API endpoint is private. DNS resolves to private IPs



---
## Step 7: Configure the Load Balancer Controller on EKS Cluster

The Ingress Controller is essential because the Kubernetes cluster itself cannot directly create external load balancers or manage sophisticated routing rules for external traffic.The Ingress Controller watches your ingress.yaml rules, provisions a load balancer, and then routes external traffic based on your configured hostnames and paths.

Note: Now you can access EKS cluster from Jump-server. 

**Download the policy for the LoadBalancer prerequisite**
```
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
```

**Create the IAM policy using the command below**
```
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json
```

**Create OIDC Provider**
```
eksctl utils associate-iam-oidc-provider --region=us-east-1 --cluster=Three-Tier-Cluster --approve
```

**Create a Service Account**

Create a Service Account by using the below command and replace your account ID with your one

```
eksctl create iamserviceaccount --cluster=Three-Tier-Cluster --namespace=kube-system --name=aws-load-balancer-controller --role-name AmazonEKSLoadBalancerControllerRole --attach-policy-arn=arn:aws:iam::<your_account_id>:policy/AWSLoadBalancerControllerIAMPolicy --approve --region=us-east-1
```
Note: Replace your <your_account_id>.

**Deploy the AWS LB Controller**

Run the below command to deploy the AWS Load Balancer Controller

```
helm repo add eks https://aws.github.io/eks-charts

helm repo update eks
```
```
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=Three-Tier-Cluster --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller

```
After 2 minutes, run the command below to check whether your pods are running or not.

```
kubectl get deployment -n kube-system aws-load-balancer-controller
```

**Note**: If the pods are getting Error or CrashLoopBackOff, then use the below command:
```
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-west-1 --set vpcId=<vpc#> -n kube-system
```
Replace vpcId=<vpc#>.

---

## Step 8: Configure SonarQube for our DevSecOps Pipeline

1. Configure SonarQube for our DevSecOps Pipeline. To do that:

- Copy your Jenkin-Server public IP and paste it into your favourite browser with a 9000 port

- The username and password will be admin.

- Click on Log In.

- Update the password

- Click on Administration, then Security, and select Users

- Click on Update tokens (symbol will be there)

- Click on Generate

- Provide the **name** (three-tier)

- Copy the token, keep it somewhere safe and click on Done. **(Sonar-token --> will use in jenkins credentials)**


2. Configure webhooks for quality checks:

- Click on Administration, then Configuration, and select Webhooks

- Click on Create

- Provide the **name** (jenkins) and in the **URL**, provide the Jenkins server public IP with port 8080, add sonarqube-webhook in the suffix, and click on Create **(http://<jenkin-server-public-ip>:8080/sonarqube-webhook/)**.

- create


3. Create a Project for the frontend code.

- Click on Projects 

- Select Manually

- Provide the **project display name** (frontend) to your Project 

- Provide the **project key** (frontend) 

- select **Main branch name** (main) and click on Setup

- Click on **Locally** under **overview**

- Select the **Use existing token**, provide sonar token (three-tier) and click on Continue.

- Select Other and Linux as OS.

- After performing the above steps, you will get the command. We will use the command in the Jenkins Frontend Pipeline where Code Quality Analysis will be performed. **(frontend code--> will use in jenkins pipeline)**


4. Now, create a Project for the backend code.

- Click on Projects 

- Select Manually

- Provide the **project display name** (backend) to your Project 

- Provide the **project key** (backend) 

- select **Main branch name** (main) and click on Setup

- Click on **Locally** under **overview**

- Select the **Use existing token** and click on Continue.

- Select Other and Linux as OS.

- After performing the above steps, you will get the command. We will use the command in the Jenkins backend Pipeline where Code Quality Analysis will be performed. **(backend code--> will use in jenkins pipeline)**

Note: “In production, SonarQube requires external PostgreSQL and persistent volumes.”

---


## Step 9: Create Amazon ECR Private Repositories for both Tiers (Frontend & Backend)

1. We need to create Amazon ECR Private Repositories for Frontend Tier

- Navigate to AWS console

- Go to ECR

- Click on Create repository

- Select the **Private** option to provide the repository 

- Provide the name **frontend** and click on Save.


2. We need to create Amazon ECR Private Repositories for Backend Tier as well

- Navigate to AWS console

- Go to ECR

- Click on Create repository

- Select the **Private** option to provide the repository 

- Provide the name **backend** and click on Save.


3. Now, we need to configure ECR locally because we have to upload our images to Amazon ECR.

- Navigate to repositories

- Select either one from frontend or backend repository

- Click on **View Push commands**

- Copy the 1st command for login

4. Now, run the copied command on your Jenkins Server inorder to login to the repositories.


**IMPORTANT NOTE**:

As our ECR repositories are private, Kubernetes cannot pull images without authentication.
Even though Jenkins-server successfully pushes images to ECR, Kubernetes nodes do not automatically have access to private registries. When a pod tries to pull an image from a private ECR repository without credentials, it results in an ImagePullBackOff error.

To resolve this, we need to create a Kubernetes Docker registry secret using credentials stored in the .docker/config.json file (generated during ECR login). This secret is then referenced in the deployment manifest using imagePullSecrets.


**We will be deploying our application on a three-tier namespace. To do that, we will create a three-tier namespace on EKS**
```
kubectl create namespace three-tier
```

**we will create a secret for our ECR Repo by the below command and then, we will add this secret name (ecr-registry-secret) to k8s deployment files**
```
kubectl create secret generic ecr-registry-secret \
  --from-file=.dockerconfigjson=${HOME}/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson --namespace three-tier

kubectl get secrets -n three-tier
```
Note: “This secret is namespace-scoped and only valid for the three-tier namespace.”

---



## Step 10: Install required plugins and configure credentials in Jenkins

Let's install the required jenkins plugins and configure credentials in jenkins to fetch and access respective tool/service by jenkins.

### Install Plugins

**Access Jenkins and Go to Dashboard -> Manage Jenkins -> Plugins**:

* AWS credentials
* Pipeline : AWS steps
* Pipeline : Stage view
* Docker 
* Docker Pipeline
* Docker API
* Docker commons
* NodeJS
* OWASP Dependency-Check
* SonarQube Scanner


### Configure credentials in Jenkins

“In production, AWS credentials should come from the EC2 instance profile, not Jenkins credentials.”

**Access Jenkins and Go to Dashboard -> Manage Jenkins -> Credentials**:

```
http://<Jenkin-Server_PUBLIC_IP>:8080
```

**1. Sonarqube credentials**

Note: We will use this credential to pass to jenkinsfile script to fetch it to get access to Sonarqube projects.

- Select the kind as *Secret text*, 

- paste your token in Secret (sonar-token)

- provide ID as **sonar-token**

- keep other things as it is.

- Click on Create

**2. GitHub credentials**

Jenkins uses two GitHub credentials because Git checkout is handled by the Jenkins Git plugin, while Git push is executed via shell commands. Each requires a different credential type.

1. Used for Git CHECKOUT in jenkinsfile:

This credential is used by the Jenkins Git plugin during the git checkout stage in the Jenkinsfile.

- Select the kind as Username with password

- scope Global
 
- provide Username as **anikhilt600**

- Password: paste your GitHub Personal access token (not password) in Secret

- provide ID as **GITHUB**

- keep other things as it is.

- Click on Create


2. Used for Git PUSH (Manifest Update) in jenkinsfile :

This credential is used when Jenkins performs a CLI-based git push to update Kubernetes manifests with the new image tag.

- Select the kind as Secret text 

- paste your GitHub Personal access token (not password) in Secret

- provide ID as **github**

- keep other things as it is.

- Click on Create

If you haven’t generated your token, you generate it first, then paste it into the Jenkins


**3. AWS credentials**

We need to add AWS Account secrets in the Jenkins credentials to interact with AWS.

Note: We will use this credential to pass to jenkinsfile script to connect and access AWS services.

- Select the kind as AWS Credentials

- Select Scope as Global

- provide ID as **aws_creds**

- provide Access key and Secret key from step 1

- keep other things as it is.

- Click on Create


**4. AWS Account ID credentials**

Now, according to our Pipeline, we need to add an Account ID in the Jenkins credentials because of the ECR repo URI.

Note: We will use this credential to pass to jenkinsfile script to form command to get ECR repo and image.


- Select the kind as Secret text

- paste your AWS Account ID in Secret 

- keep other things as it is.

- Click on Create


**5. Frontend ECR Repo credentials**

We need to provide our ECR repo name for the frontend, which is frontend only.

Note: We will use this credential to pass to jenkinsfile script to form command to get frontend ECR repo and image.

- Select the kind as Secret text

- paste your frontend repo name in Secret (**frontend**)

- provide ID as **ECR_REPO_FRONTEND**

- keep other things as it is.

- Click on Create


**6. Backend ECR Repo credentials**

We need to provide our ECR repo name for the backend, which is backend only.

Note: We will use this credential to pass to jenkinsfile script to form command to get backend ECR repo and image.

- Select the kind as Secret text

- paste your backend repo name in Secret (**backend**)

- provide ID as **ECR_REPO_BACKEND**

- keep other things as it is.

- Click on Create


### Configure the installed plugins

We have to configure the installed plugins as below

**Access Jenkins and Go to Dashboard -> Manage Jenkins -> Tools**:


**A: Configuring JDK**

Search for *JDK Installations* and provide the configuration:

- Name : jdk

- Check select-box for Install Automatically


**B: Configure SonarQube scanner**

Search for the *SonarQube scanner* and provide the configuration like below:

- Add SonarQube Scanner

- Name : sonar-scanner

- Check select-box for Install Automatically


**C: Configure nodejs**

Search for the *NodeJS* and provide the configuration, like below:

- Add NodeJS

- Name : nodejs

- Check select-box for Install Automatically


**D: Configure the OWASP Dependency Check**

Search for *Dependency-Check Installtions* and provide the configuration like below:

- Add Dependency-Check

- Name : DP-Check

- Check select-box for Install Automatically


**E: Configure the Docker**

Search for *Docker* and provide the configuration like below:

- Add Docker

- Name : docker

- Check select-box for Install Automatically


Click on Apply and Save


### Set the path for SonarQube in Jenkins

**Access Jenkins and Go to Dashboard -> Manage Jenkins -> System**:

Search for *SonarQube Servers* --> *SonarQube Installtions*

Provide the name as it is, then in the Server URL, copy the SonarQube public IP (same as Jenkins) with port 9000, select the Sonar token that we have added recently, and click on Apply & Save.

- Add SonarQube Installtions

- Name : sonar-server

- Server URL : copy the SonarQube server public IP (same as Jenkin-server ec2) with port 9000
  
   - Example : http://23.51.134.256:9000

- Server Authentication Token:  select the Sonar-token (credential) that we have added recently

- Click on Apply & Save.


Great going, we are ready to create our Jenkins Pipeline to deploy our app.

---


## Step 11: Build Jenkin pipelines (Backend, Frontend) 

Below pipelines automates the security and quality analysis of a Node.js frontend and backend by scanning the code with SonarQube, OWASP Dependency-Check, and Trivy. It ensures DevSecOps best practices by enforcing a Quality Gate and checking for vulnerabilities in both the source code and its dependencies. Finally, it prepares the application for deployment by building a Docker image to be hosted on AWS ECR.


### Backend 

Now, we are ready to create our Jenkins Pipeline to deploy our Backend Code.

- Go to Jenkins Dashboard --> Click on New Item --> name (three-tier-backend) --> select Pipeline --> Click on OK.

- Nagivate to created pipelibe (three-tier-backend) --> Configuration --> pipeline --> Defination (select pipeline script)

- Copy and paste this into the Script *\Jenkins-Pipeline-Script\Jenkinsfile-Backend*

- Click Apply & Save

- Now, click on the build.


### Frontend 

Now, we are ready to create our Jenkins Pipeline to deploy our Frontend Code.

- Go to Jenkins Dashboard --> Click on New Item --> name (three-tier-frontend) --> select Pipeline --> Click on OK.

- Nagivate to created pipelibe (three-tier-frontend) --> Configuration --> pipeline --> Defination (select pipeline script)

- Copy and paste this into the Script *\Jenkins-Pipeline-Script\Jenkinsfile-Frontend*

- Click Apply & Save

- Now, click on the build.


Note: “Jenkins pipelines stop after pushing images; deployment is handled by ArgoCD.”


**Here is an explanation of the core concepts for each stage used in Jenkins pipeline**:

1. Cleaning Workspace

The Concept: Environment Isolation.

What it does: It removes any temporary files, previous build artifacts, or old code left over from earlier runs. This ensures that a failure in a previous build doesn't "pollute" or break the current build.

2. Checkout from Git

The Concept: Source Control Integration.

What it does: It pulls the specific version of the source code from your GitHub repository into the Jenkins agent. This is the foundation of CI (Continuous Integration), ensuring the pipeline always runs on the most recent code changes.

3. Sonarqube Analysis

The Concept: Static Application Security Testing (SAST).

What it does: It "reads" your code without running it to find bugs, technical debt, and security hotspots. It checks if the code follows best practices and highlights areas that might be difficult to maintain.

Note: We usually share this reports with developer team to fix the application code accordingly.

4. Quality Check

The Concept: Governance & Compliance.

What it does: This acts as a "stop sign." It talks to the SonarQube server and asks: "Did the code pass the minimum requirements?" If the code has too many bugs or vulnerabilities, it fails the pipeline here to prevent bad code from reaching production.

5. OWASP Dependency-Check Scan

The Concept: Software Composition Analysis (SCA).

What it does: It focuses on third-party libraries (the packages in your package.json). It compares your project's dependencies against a huge database of known vulnerabilities (CVEs) to ensure you aren't using a library that hackers have already exploited.

**Note: This will take 15-25 minutes, so we will comment this out in this demo.**

6. Trivy File Scan

The Concept: Vulnerability & Misconfiguration Scanning.

What it does: Trivy looks for "low-hanging fruit" security risks. In this stage (filesystem scan), it looks for hardcoded passwords, secrets, or insecure configuration files within your project folder that shouldn't be there.

7. Docker Image Build

The Concept: Immutable Infrastructure.

What it does: It cleans up old Docker data (prune) to save disk space and then uses a Dockerfile to bundle your frontend code into a lightweight, runnable container image. This image contains everything the app needs to run, ensuring it works exactly the same in testing as it does in production.

8. ECR Image Pushing

The Concept: Artifact Registry Management.

What it does: It logs into your private AWS ECR (Elastic Container Registry) and uploads (pushes) the newly built image. It uses the BUILD_NUMBER as a unique version tag so you can track exactly which Jenkins build produced which container image.

9. TRIVY Image Scan

The Concept: Dynamic Container Security.

What it does: Unlike the "File Scan" which checks source code, this scans the actual built image. It looks for vulnerabilities inside the Operating System layers (like Alpine or Ubuntu) and the installed system packages. It ensures the final product you are sending to AWS is secure.

10. Update Deployment File

The Concept: GitOps (Automated Deployment Trigger).

What it does: This is the most critical stage for automation. It uses sed to find the old image version in your Kubernetes deployment.yaml and replaces it with the new BUILD_NUMBER. It then commits and pushes these changes back to GitHub. This usually triggers a tool like ArgoCD or Flux to automatically deploy the new version to your cluster.


---



## Step 12: Install & Configure ArgoCD

Note: Do it on Jump-server, for our demo. Recommended to install and configure it on dedicated server.

**Troubleshooting**:
1. I was not able to open argocd UI. I troubleshoot it and found due to Single small EC2 node (t3.small) resources was exosted and argocd resources/pod was in pending state.
```
kubectl get pods -n argocd
```
2. 
- Step 1: Check your nodegroup name
```
eksctl get nodegroup --cluster demo-cluster --region us-east-1
```
- Step 2: Scale node count (add one more node)
```
eksctl scale nodegroup --cluster demo-cluster --region us-east-1 --name ng-1 --nodes 2
```
- Step 3: Verify nodes
```
kubectl get nodes
```
- Step 4: Verify argocd pods
```
kubectl get pods -n argocd
```
*End of troubleshooting*

### Install ArgoCD

Create a separate namespace for it and apply the argocd configuration for installation.

```
kubectl create namespace argocd

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.4.7/manifests/install.yaml
```

All pods must be running. To validate, run the command below

```
kubectl get pods -n argocd
```
Now, expose the argoCD server as a LoadBalancer using the below command

```
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Note: “Exposing ArgoCD via LoadBalancer is for demo only; production uses Ingress + SSO.”

You can validate whether the Load Balancer is created or not by going to the AWS Console or as below.

Once the service/argocd-server patched, run the below command to get the argocd-server external IP/DNS to access the UI on browser:

```
kubectl get svc -n argocd
```
*Example argocd-server external IP/DNS : abc84g52849gwjkwryr8462dfy-hrqo6iksn.us-est-1.elb.amazonaws.com*


### ArgoCD UI Sign-in

Argocd UI will open on browser. Username will be *admin*.

Now, we need to get the password for our argoCD server to perform the deployment.

To do that, we have a prerequisite, which is jq. Install it by the command below:
```
sudo apt install jq -y
```
```
export ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o json | jq -r '.status.loadBalancer.ingress[0].hostname')

export ARGO_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
```

Enter the username and password in argoCD browser UI and click on SIGN IN.

---



## Step 13: Deploy our Three-Tier Application using ArgoCD

### Github Repo connectivity

We will deploy our Three-Tier Application using ArgoCD. As our repository is private, we need to configure the Private Repository in ArgoCD.

- Click on Settings and select Repositories

- Click on CONNECT REPO USING HTTPS

- Type : git

- project : default

- Repository URL : Provide the repository name where your Manifest files are present.
         
         Example : https://github.com/ANIKHILT600/devops-mern-stack.git

- Username (optional) : Provide the username (if your repo is private then requires)

- Password (optional) : GitHub Personal Access token (if your repo is private then requires)

- Click on CONNECT.

If your Connection Status is Successful, it means the repository connected successfully.

### 1. DATABASE APP

First, we will create our database application in argoCD:

- Click on CREATE APPLICATION

- Application Name : database

- Project name : default

- SYNC POLICY : Automatic (Check AUTO HEAL)

- Repository URL : https://github.com/ANIKHILT600/devops-mern-stack.git

- Revision : HEAD

- Path : K8s-Manifests/Database

- Cluster URL :  (select default one) https://kubernetes.default.svc

- Namespace : three-tier

- Click on CREATE.

While your database Application is starting to deploy, we will create an application for the backend.

### 2. BACKEND APP

We will create our backend application in argoCD:

- Click on CREATE APPLICATION

- Application Name : backend

- Project name : default

- SYNC POLICY : Automatic (Check AUTO HEAL)

- Repository URL : https://github.com/ANIKHILT600/devops-mern-stack.git

- Revision : HEAD

- Path : K8s-Manifests/Backend

- Cluster URL :  (select default one) https://kubernetes.default.svc

- Namespace : three-tier

- Click on CREATE.

While your backend Application is starting to deploy, we will create an application for the frontend.

### 3. FRONTEND APP

We will create our frontend application in argoCD:

- Click on CREATE APPLICATION

- Application Name : frontend

- Project name : default

- SYNC POLICY : Automatic (Check AUTO HEAL)

- Repository URL : https://github.com/ANIKHILT600/devops-mern-stack.git

- Revision : HEAD

- Path : K8s-Manifests/Frontend

- Cluster URL :  (select default one) https://kubernetes.default.svc

- Namespace : three-tier

- Click on CREATE.

While your frontend Application is starting to deploy, we will create an application for the ingress.

### 4. Ingress APP

We will create our ingress application in argoCD:

- Click on CREATE APPLICATION

- Application Name : ingress

- Project name : default

- SYNC POLICY : Automatic (Check AUTO HEAL)

- Repository URL : https://github.com/ANIKHILT600/devops-mern-stack.git

- Revision : HEAD

- Path : K8s-Manifests/ingress

- Cluster URL :  (select default one) https://kubernetes.default.svc

- Namespace : three-tier

- Click on CREATE.

Once your Ingress application is deployed. It will create an Application Load Balancer. You can check out the load balancer named *k8s-three-tier-mainlb-1234567890.us-east-1.elb.amazonaws.com* using below in ADDRESS:

```
kubectl get ing -n three-tier
```

---

## 14. Configure DNS

Assuming:

- You already own the domain tarangan.tk (from another registrar)

- Your application is deployed on EKS

- An AWS ALB is created by the Kubernetes Ingress (via AWS Load Balancer Controller)

**We are configuring DNS using Amazon Route 53**:

### A. Verify AWS ALB is created by the Kubernetes Ingress
```
kubectl get ingress -n three-tier
```

You will see **ALB-DNS-NAME** something like:

ADDRESS:

k8s-three-tier-mainlb-1234567890.us-east-1.elb.amazonaws.com


**Important Note: If you are managing your subdomain for example claudflare then NO NEED to create route53 just add your ingress ALB to claudflare DNS CNAME record (disable proxy).**


### B. Create a Hosted Zone in Route53

Even though the domain is registered elsewhere, you must create a Hosted Zone in Route53.

- Go to AWS Console → Route53

- Click Hosted zones

- Click Create hosted zone

- Configuration

- Domain name: tarangan4u.dpdns.org

- Type: Public Hosted Zone

- Create

**After creation, Route53 will generate 4 Name Servers (NS)** Example:

ns-123.awsdns-45.org

ns-678.awsdns-90.co.uk

ns-abc.awsdns-12.com

ns-xyz.awsdns-34.net


### C. Update Name Servers at Your Domain Provider

Now go to your domain registrar (where you bought [tarangan4u.dpdns.org](https://dash.domain.digitalplat.org/panel/main?page=%2Fpanel%2Fmanager%2Ftarangan4u.dpdns.org)) and Replace the existing name servers with the Route53 NS records.


**This step is mandatory — without it, Route53 will NOT receive DNS queries.**

⏱️ Propagation time: Usually 5–30 minutes. Can take up to 24 hours (rare)


### D. Create DNS Records in Route53

Now Route53 is authoritative for your domain.

**Option A: Use Alias Record (Recommended for root domain)**

If you want: http://tarangan4u.dpdns.org

**Use:**

Create record

Record type: A

Alias: Yes

Alias target / Route traffic to : Alias to Application and Classic Load Balancer

Choose region : us-east-1

Choose Load balancer : <ALB-DNS-NAME>

Create record


**Option B: Use CNAME (most common with ALB)**

Create records like:

Frontend

Record name: frontend.tarangan4u.dpdns.org

Type: CNAME

Value: <ALB-DNS-NAME>

TTL: 300


Backend / API

Record name: api.tarangan4u.dpdns.org

Type: CNAME

Value: <ALB-DNS-NAME>

TTL: 300


This works because: ALB DNS name is public. Subdomains can use CNAME



### E. Ensure Ingress host Matches DNS

Your ingress.yaml must match DNS exactly. If host ≠ DNS name → traffic will be dropped.

Example:
```
spec:
  rules:
  - host: tarangan4u.dpdns.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 3000
```



### F. Enable HTTPS (Optional but Production-Critical) 

**Option A: AWS Certificate Manager (Recommended)**

Request certificate in ACM:

frontend.tarangan.tk

api.tarangan.tk

Validate via DNS (Route53 auto-validation)

Update Ingress annotations:

alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...

alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'


### G. Verify End-to-End

nslookup frontend.tarangan.tk

curl https://frontend.tarangan.tk

Or simply open browser.

Now, you can configure your monitoring with prometheus and Grafana Dashboard to view the EKS data, such as pods, namespace, deployments, etc.

---


## Step 15: Monitoring with Prometheus & Grafana

We will set up the Monitoring for our EKS Cluster. We can monitor the Cluster Specifications and other necessary things.

1. We will achieve the monitoring using Helm. Add the Prometheus repo by using the command below:
```
helm repo add stable https://charts.helm.sh/stable
```

2. Install the Prometheus

Note: “In production, Prometheus uses kube-prometheus-stack or Amazon Managed Prometheus.”

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo update

helm install prometheus prometheus-community/prometheus
```

3. Install the grafana
```
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

helm install grafana grafana/grafana
```

4. Check the service by the command below
```
kubectl get svc
```

5. Access our Prometheus and Grafana consoles

To access our Prometheus and Grafana consoles from outside of the cluster, we need to change the Service type from ClusterType to LoadBalancer

- 5.a : Edit the stable-kube-prometheus-sta-prometheus service and Modify in the 48th line from ClusterIP to LoadBalancer.
```
kubectl edit svc stable-kube-prometheus-sta-prometheus
```

- 5.b : Edit the stable-grafana service and Modification in the 39th line from ClusterType to LoadBalancer.
```
kubectl edit svc stable-grafana
```

- 5.c : If you list the service again, then you will see the LoadBalancers' DNS names. You can also validate from your console.
```
kubectl get svc
```

- 5.d :  **access your Prometheus Dashboard**

Paste the <Prometheus-LB-DNS>:9090 in your favourite browser, and you will see UI.

Click on Status and select Target. You will see a lot of Targets

- 5.e : **access your Grafana Dashboard**

Copy the ALB DNS of Grafana and paste it into your favourite browser. The username will be admin, and the password will be prom-operator for your Grafana LogIn.

- click on Data Source

- Select Prometheus

- Name : Prometheus-1

- In the Connection, paste your <Prometheus-LB-DNS>:9090

- If the URL is correct, then you will see a green notification/

- Click on Save & test.


6. Create a dashboard to visualise our Kubernetes Cluster Logs.

- In Grafana Click on Dashboard (You will see a lot of Kubernetes components being monitored)

- Let’s try to import a type of Kubernetes Dashboard.

       : Click on New and select Import

       : Provide 6417 ID and click on Load (6417 is a unique ID from Grafana, used to monitor and visualise Kubernetes Data)

       : Select the data source that you have created earlier (Prometheus-1) and click on Import.

- Here, you go. You can view your Kubernetes Cluster Data.

Feel free to explore the other details of the Kubernetes Cluster.

---


## 16. Validation Database Persistent Volume

We have created the Database Application Deployment in ArgoCD

If you observe in argoCD UI, we have configured the Persistent Volume & Persistent Volume Claim. So, if the pods get deleted, then the data won’t be lost. The Data will be stored on the host machine.

To validate it, delete both Database pods and the new pods will be started. Your Application won’t lose a single piece of data.

---

## Conclusion

In this project, we successfully:

* Built infrastructure
* Implemented Jenkins CI/CD with security scanning
* Deployed MERN application on AWS EKS
* Used GitOps with ArgoCD
* Enabled monitoring with Prometheus & Grafana
* Ensured persistent data storage

🎉 **Congratulations on completing a full-scale production-grade DevSecOps project!**