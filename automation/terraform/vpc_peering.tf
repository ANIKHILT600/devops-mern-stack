# ═══════════════════════════════════════════════════════════════════════
# VPC PEERING: Management VPC ↔ Production VPC
# ═══════════════════════════════════════════════════════════════════════
# Purpose: Enable Jenkins (mgmt VPC) to reach private EKS API endpoint
#          (prod VPC) without internet routing
#
# Design: Bidirectional routing via VPC peering connection
#         10.0.0.0/16 (mgmt) ↔ 192.168.0.0/16 (prod)
#
# Security: Security groups control actual connectivity (HTTPS port 443)
#           VPC peering simply enables network path
# ═══════════════════════════════════════════════════════════════════════

# Step 1: Create VPC Peering Connection
# ─────────────────────────────────────────────────────────────────────

resource "aws_vpc_peering_connection" "mgmt_to_prod" {
  vpc_id      = module.vpc_mgmt.vpc_id
  peer_vpc_id = module.vpc_eks.vpc_id

  tags = {
    Name = "mgmt-to-prod-peering"
    Side = "Requester"
  }
}

# Step 2: Accept the Peering Connection (auto-accept for same-account)
# ─────────────────────────────────────────────────────────────────────

resource "aws_vpc_peering_connection_accepter" "prod_accepts_mgmt" {
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_to_prod.id
  auto_accept               = true

  tags = {
    Name = "mgmt-to-prod-peering"
    Side = "Accepter"
  }
}

# Step 3: Add Peering Routes to Management VPC Route Table
# ─────────────────────────────────────────────────────────────────────
# Management public servers → Production VPC (192.168.0.0/16)

resource "aws_route" "mgmt_to_prod" {
  route_table_id            = module.vpc_mgmt.route_table_public_id
  destination_cidr_block    = "192.168.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_to_prod.id

  depends_on = [
    aws_vpc_peering_connection_accepter.prod_accepts_mgmt
  ]
}

# Step 4: Add Peering Routes to Production VPC Route Table (Private)
# ─────────────────────────────────────────────────────────────────────
# Production private nodes need reverse route to mgmt for return traffic

resource "aws_route" "prod_to_mgmt" {
  route_table_id            = module.vpc_eks.route_table_private_id
  destination_cidr_block    = "10.0.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_to_prod.id

  depends_on = [
    aws_vpc_peering_connection_accepter.prod_accepts_mgmt
  ]
}

# Step 5: Allow Jenkins (mgmt VPC) to reach EKS Control Plane API (port 443)
# ─────────────────────────────────────────────────────────────────────────────
# The EKS control plane has an auto-managed security group. We reference it
# and add an ingress rule to allow management VPC HTTPS traffic.

resource "aws_security_group_rule" "eks_cluster_allow_mgmt_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = module.eks.cluster_security_group_id
  description       = "Allow Jenkins (mgmt VPC) HTTPS access to EKS private API endpoint"
}
