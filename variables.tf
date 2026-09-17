variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "gavok-zt"
}

variable "kubernetes_version" {
  description = <<-EOT
    EKS Kubernetes version. Pinned one minor behind fred01's 1.36 for a
    safer Istio ambient-mode compatibility margin -- confirm Istio's
    supported Kubernetes range at istio.io/latest/docs/releases/supported-releases
    before bumping this to 1.36.
  EOT
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.60.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "on_demand_instance_types" {
  description = "Instance types for the 'gavok' on-demand node group (istiod, spire-server land here)"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "spot_instance_types" {
  description = "Instance types for the 'kwok' spot node group (everything else)"
  type        = list(string)
  default     = ["m6i.large", "m5.large", "m5a.large"]
}

variable "mirrored_images" {
  description = "Third-party images mirrored into private ECR (no-NAT means no public pulls from nodes)"
  type        = list(string)
  default = [
    "istio-pilot",
    "istio-ztunnel",
    "istio-install-cni",
    "istio-proxyv2",
    "spire-server",
    "spire-agent",
  ]
}
