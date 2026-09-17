# NOTE ON MODULE VERSION: v21 renamed several cluster_* arguments
# (cluster_name -> name, cluster_version -> kubernetes_version,
# cluster_encryption_config -> encryption_config, among others) and
# replaced the aws-auth ConfigMap with access_entries. You already fought
# through this exact migration on fred01.
#
# eks_managed_node_group_defaults was removed outright in v21 -- there is
# no more shared-defaults block. Settings go directly into each node
# group now, so the local below + merge() below stands in for it.

locals {
  node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"

    # v21 also quietly changed the IMDS hop-limit default from 2 back
    # down to 1, which reopens the exact node-join issue from fred01.
    # Same fix, just applied per-node-group instead of via a shared
    # defaults block.
    metadata_options = {
      http_tokens                 = "required"
      http_put_response_hop_limit = 2
    }
  }
}

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
    resources        = ["secrets"]
  }

  # v21 disabled the old automatic "bootstrap_self_managed_addons" path
  # entirely -- without this block, node groups come up with no CNI and
  # nodes never go Ready. These pull from AWS's own per-region EKS addon
  # ECR repos, not docker.io/ghcr.io, so they're already reachable through
  # the ecr.api/ecr.dkr endpoints in vpc.tf -- no extra mirroring needed,
  # unlike Istio/SPIRE later.
  #
  # before_compute = true on vpc-cni specifically: by default this module
  # creates addons AFTER node groups (addons depend on the node group
  # modules completing). Backwards for vpc-cni, which nodes need in order
  # to go Ready in the first place -- without this flag it deadlocks: node
  # groups wait on CNI to make nodes Ready, CNI waits on node groups to
  # finish, node group health-check timeout wins and the whole thing fails
  # CREATE_FAILED. This flips vpc-cni to create before the node groups.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    coredns    = {}
    kube-proxy = {}
  }

  eks_managed_node_groups = {
    # On-demand: control-plane-adjacent workloads (istiod, spire-server
    # later) that shouldn't get reclaimed mid-demo.
    gavok = merge(local.node_group_defaults, {
      instance_types = var.on_demand_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 4
      desired_size   = 1
    })
    # Spot: everything else (ztunnel DaemonSet runs on both groups by
    # design; demo workloads land here).
    kwok = merge(local.node_group_defaults, {
      instance_types = var.spot_instance_types
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 4
      desired_size   = 1
    })
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
