# End-to-End MERN Stack DevSecOps Project on AWS EKS

## Table of Contents

- [Project Overview](#project-overview)
- [Prerequisites](#prerequisites)
- [Manual Implementation](#manual-implementation)
- [Automation Implementation](#automation-implementation)

---

## Project Overview

In this project, we cover a **End-to-End DevSecOps implementation** for a **Three-Tier Application (MERN Stack )** deployed on **AWS EKS**.

**Key aspects covered:**

* **IAM User Setup**: Create an IAM user on AWS with the necessary permissions to facilitate deployment and management activities.
* **Infrastructure as Code (IaC)**: Use Terraform and AWS CLI to set up the Jenkins server (EC2 instance) on AWS.
* **Jenkins Server Configuration**: Install and configure essential tools on the Jenkins server, including Jenkins itself, Docker, Sonarqube, Terraform, Kubectl, AWS CLI, and Trivy.
* **EKS Cluster Deployment**: Utilise eksctl commands to create an Amazon EKS cluster, a managed Kubernetes service on AWS.
* **Load Balancer Configuration**: Configure AWS Application Load Balancer (ALB) for the EKS cluster.
* **Amazon ECR Repositories**: Create private repositories for both frontend and backend Docker images on Amazon Elastic Container Registry (ECR).
* **ArgoCD Installation**: Install and set up ArgoCD for continuous delivery and GitOps.
* **Sonarqube Integration**: Integrate Sonarqube for code quality analysis in the DevSecOps pipeline.
* **Jenkins Pipelines**: Create Jenkins pipelines for deploying backend and frontend code to the EKS cluster.
* **Monitoring Setup**: Implement monitoring for the EKS cluster using Helm, Prometheus, and Grafana.
* **ArgoCD Application Deployment**: Use ArgoCD to deploy the Three-Tier application, including database, backend, frontend, and ingress components.
* **DNS Configuration**: Configure DNS settings to make the application accessible via custom subdomains.
* **Data Persistence**: Implement persistent volumes and persistent volume claims for database pods to ensure data persistence.
* **Conclusion and Monitoring**: Conclude the project by summarising key achievements and monitoring the EKS cluster’s performance using Grafana.

---

## Prerequisites

Before starting the project, ensure you have the following prerequisites:

* An AWS account with the necessary permissions to create resources.
* Terraform and AWS CLI are installed on your local machine.
* Basic familiarity with Kubernetes, Docker, Jenkins, and DevOps principles.

---

**Our approch here “First manual, then full automation”**

## [MANUAL IMPLEMENTATION](/Manual_Implementation.md)
* Goal: Understand every component, every dependency, and every decision by doing things manually.


## [Automation IMPLEMENTATION](/Automation_Implementation.md)
* Goal: Zero-click deployments after code push.