# Phase 1 Runbook: gavok-zt Cluster Foundation

Foundation layer for the zero-trust service mesh project. A dedicated EKS
cluster — deliberately **not** fred01 — built on the established no-NAT /
VPC-endpoint-only / ECR-mirror-only pattern, with ECR repos and image
mirroring staged for Phase 2 (Istio ambient mode).

## Why a new cluster, not fred01
fred01 already carries ArgoCD, Kyverno, and kube-prometheus-stack, and its
image-mirroring pipeline was flagged as producing bad tags at one point.
Rather than stack Istio's control plane and SPIRE on top of a mirroring
process that's still unverified, this keeps the new project's inevitable
early failures isolated from the existing GitOps stack.

## What this phase builds
- VPC across 2 AZs, private + public subnets, **no NAT Gateway**
- 7 VPC endpoints (S3 gateway + 6 interface: ec2, ecr.api, ecr.dkr, sts, logs, kms, elasticloadbalancing)
- KMS key for EKS secrets envelope encryption
- EKS control plane
- Two managed node groups: `gavok` (on-demand) and `kwok` (spot)
- 6 private ECR repos under `mirror/*`, ready for Istio + SPIRE images

## Kubernetes version note
Pinned to **1.34** here instead of matching fred01's 1.36. Istio 1.30.x's
supported Kubernetes range wasn't fully confirmed against 1.36 as of
writing this. Before Phase 2, check
https://istio.io/latest/docs/releases/supported-releases — if 1.36 is
supported by then, bump `kubernetes_version` in `terraform.tfvars` and
re-apply before installing Istio.

## Prerequisites
- Terraform >= 1.11 (`terraform version`) — required for S3 native locking
- AWS CLI v2, configured with credentials that can create VPC/EKS/KMS/ECR
- Docker, with `--platform linux/amd64` if you're on Apple Silicon (same
  fix already documented from ShopSecure)
- An S3 bucket for Terraform state, created *before* `terraform init` —
  a backend block can't create its own backend

## Step 0 — Create the state bucket
```bash
aws s3api create-bucket \
  --bucket gavok-zt-tfstate \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket gavok-zt-tfstate \
  --versioning-configuration Status=Enabled
```
Bucket names are global — if `gavok-zt-tfstate` is taken, pick another
and update `backend.tf` accordingly (replace `REPLACE-ME-gavok-zt-tfstate`).

## Step 1 — Set variables
```bash
cp terraform.tfvars.example terraform.tfvars
```
Defaults match the description above. Adjust `azs` for a 3rd AZ, or the
instance type lists if `m6i.large` isn't available in your account.

## Step 2 — Init, plan, apply
```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
Expect 12–15 minutes — EKS control plane provisioning is the long pole.

## Step 3 — Configure kubectl
```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```
You should see nodes from both the `gavok` and `kwok` node groups, `Ready`.

## Step 4 — Mirror images
```bash
cd scripts
chmod +x mirror-images.sh
AWS_REGION=us-east-1 ./mirror-images.sh
```
Pulls Istio ambient-mode images (pilot, ztunnel, install-cni, proxyv2) and
SPIRE (server, agent), pushes them into the ECR repos Terraform just
created. SPIRE isn't deployed until Phase 3 — mirroring it now is just one
less thing to do later. Comment those two `mirror` lines out in the script
if you'd rather defer it.

## Step 5 — Verify
```bash
terraform output ecr_repository_urls
aws ecr describe-images --repository-name mirror/istio-pilot --region us-east-1
kubectl get nodes -o wide
```

## Troubleshooting
Issues already hit once on fred01 — pre-empted in this config, flagged
here in case they resurface:

- **Node join failures.** IMDSv2 hop limit is set to 2 in `eks.tf`
  (`eks_managed_node_group_defaults.metadata_options`), and the cluster→
  node 443 rule is explicit in `node_security_group_additional_rules`. If
  nodes still won't join, check that the VPC endpoint security group
  allows 443 inbound from the node subnets — that's the other half of
  what bit fred01.
- **`terraform plan` / `terraform init` complains about an unknown argument in `eks.tf`.**
  Already hit and fixed once: v21 removed `eks_managed_node_group_defaults`
  entirely (confirmed against the module's own v21 upgrade guide) — shared
  node-group settings now go directly into each node group, which is why
  `eks.tf` uses a `local.node_group_defaults` + `merge()` instead. If a
  *different* argument trips this, diff against fred01's working config
  before troubleshooting from scratch.
- **Stale `.terraform` cache** after any module version change:
  `rm -rf .terraform .terraform.lock.hcl` and re-run `terraform init`.
- **ECR pulls fail once workloads land.** Confirm the `ecr.api` /
  `ecr.dkr` VPC endpoints have `private_dns_enabled = true` (already set
  here) — without it, nodes resolve ECR's public DNS and have no NAT
  Gateway to reach it.

## Next: Phase 2
Install istiod + ztunnel in ambient mode, pointed at the ECR mirror
instead of docker.io, and set a default-deny `AuthorizationPolicy` so
nothing talks to anything until it's explicitly allowed.
