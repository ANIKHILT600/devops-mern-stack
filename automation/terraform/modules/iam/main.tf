variable "project_name" {}

resource "aws_iam_role" "jenkins" {
  name = "${var.project_name}-jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# ─────────────────────────────────────────────────────────────
# JENKINS LEAST-PRIVILEGE INLINE POLICY
# Replaces AdministratorAccess with scoped permissions for CI/CD
# Prevents full AWS account compromise if Jenkins is compromised
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role_policy" "jenkins_scoped" {
  name = "${var.project_name}-jenkins-policy"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ─── EC2 COMPUTE ───
      {
        Sid    = "EC2ManageInstances"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:RebootInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeImages",
          "ec2:DescribeAvailabilityZones",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      # ─── EBS VOLUMES ───
      {
        Sid    = "EBSVolumeManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      # ─── SECURITY GROUPS & NETWORKING ───
      {
        Sid    = "SecurityGroupManagement"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      # ─── ECR (DOCKER REGISTRY) ───
      {
        Sid    = "ECRRegistryAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:GetAuthorizationToken",
          "ecr:BatchDeleteImage"
        ]
        Resource = "*"
      },
      # ─── EKS CLUSTER MANAGEMENT ───
      {
        Sid    = "EKSClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:CreateCluster",
          "eks:UpdateClusterVersion",
          "eks:DeleteCluster",
          "eks:CreateNodegroup",
          "eks:DeleteNodegroup"
        ]
        Resource = "*"
      },
      # ─── IAM PASS-ROLE (Allow Jenkins to use roles) ───
      {
        Sid    = "IAMPassRoleForServices"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/*-eks-cluster-role",
          "arn:aws:iam::*:role/*-eks-node-role",
          "arn:aws:iam::*:role/*-jenkins-role"
        ]
      },
      # ─── STS FOR IRSA & CROSS-ACCOUNT ───
      {
        Sid    = "STSAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      # ─── CLOUDFORMATION (IaC) ───
      {
        Sid    = "CloudFormationManagement"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateStack",
          "cloudformation:UpdateStack",
          "cloudformation:DeleteStack",
          "cloudformation:DescribeStacks",
          "cloudformation:ListStacks",
          "cloudformation:GetTemplate",
          "cloudformation:DescribeStackResource",
          "cloudformation:DescribeStackResources",
          "cloudformation:ValidateTemplate"
        ]
        Resource = "*"
      },
      # ─── S3 (TERRAFORM STATE + ARTIFACTS) ───
      {
        Sid    = "S3TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:ListBucketVersions"
        ]
        Resource = "*"
      },
      # ─── DYNAMODB (TERRAFORM LOCK) ───
      {
        Sid    = "DynamoDBTerraformLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "*"
      },
      # ─── CLOUDWATCH LOGS ───
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      # ─── SSM PARAMETER STORE (SECRETS) ───
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:GetParameters",
          "ssm:DescribeParameters"
        ]
        Resource = "*"
      },
      # ─── VPC PEERING (NETWORKING) ───
      {
        Sid    = "VPCPeeringManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpcPeeringConnection",
          "ec2:AcceptVpcPeeringConnection",
          "ec2:DeleteVpcPeeringConnection",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:RejectVpcPeeringConnection"
        ]
        Resource = "*"
      },
      # ─── KMS (ENCRYPTION) ───
      {
        Sid    = "KMSEncryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# IAM PERMISSIONS BOUNDARY (OPTIONAL FUTURE)
# Prevents Jenkins role from escalating beyond these permissions
# Can be attached to all assume-role policies
# ─────────────────────────────────────────────────────────────
# resource "aws_iam_policy" "jenkins_boundary" {
#   ... (same as jenkins_scoped policy above) ...
# }

# AWS Systems Manager (SSM) Session Manager - Production-Grade Secure Access
# Enables keyless, IAM-based access to EC2 instances without SSH keys
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

output "jenkins_profile_name" { value = aws_iam_instance_profile.jenkins.name }
output "eks_cluster_role_arn" { value = aws_iam_role.eks_cluster.arn }
output "eks_node_role_arn" { value = aws_iam_role.eks_node.arn }
