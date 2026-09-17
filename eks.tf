# NOTE ON MODULE VERSION: v21 of this module renamed several cluster_*
# arguments (cluster_name -> name, cluster_version -> kubernetes_version,
# cluster_encryption_config -> encryption_config, among others) and
# replaced the aws-auth ConfigMap with access_entries. You already fought
# through this exact migration on fred01 -- if `terraform plan` rejects an
# argument below, diff this file against fred01's working eks.tf before
# troubleshooting from scratch; that's faster than re-deriving the v21 API
# surface from the registry docs.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources         = ["secrets"]
  }

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"

    # Every node hit the IMDSv2 hop-limit issue on fred01 (default hop
    # limit of 1 breaks in-pod metadata calls). Baked the fix in here.
    metadata_options = {
      http_tokens                 = "required"
      http_put_response_hop_limit = 2
    }
  }

  eks_managed_node_groups = {
    # On-demand: control-plane-adjacent workloads (istiod, spire-server
    # later) that shouldn't get reclaimed mid-demo.
    gavok = {
      instance_types = var.on_demand_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
    # Spot: everything else (ztunnel DaemonSet runs on both groups by
    # design; demo workloads land here).
    kwok = {
      instance_types = var.spot_instance_types
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 4
      desired_size   = 1
    }
  }

  # Explicit cluster -> node 443 rule (kubelet / webhook traffic). This was
  # the other half of the fred01 node-join gap alongside the IMDSv2 fix.
  node_security_group_additional_rules = {
    ingress_cluster_443 = {
      description                   = "Cluster API to node kubelet/webhooks"
      protocol                      = "tcp"
      from_port                     = 443
      to_port                       = 443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}
