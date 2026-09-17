#!/usr/bin/env bash
# Mirrors Istio (ambient mode) + SPIRE images from public registries into
# the private ECR repos created by ecr.tf. Run AFTER `terraform apply`,
# from this scripts/ directory.
#
# Requires: docker, aws cli v2 (credentials configured), network access to
# docker.io and ghcr.io.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"

# Pin these deliberately -- verify against current releases before running:
#   https://istio.io/latest/news/releases/
#   https://github.com/spiffe/spire/releases
# Istio 1.30.3 confirmed current stable as of Sept 2026. Also re-check
# Istio's supported Kubernetes range against your cluster's version
# (see RUNBOOK.md's Kubernetes version note) before installing in Phase 2.
ISTIO_VERSION="1.30.3"
SPIRE_VERSION="1.11.2"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Logging into ${ECR_REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

mirror() {
  local src="$1" dest_repo="$2"
  echo "--- ${src} -> ${ECR_REGISTRY}/${dest_repo}:latest ---"
  # --platform linux/amd64 matters on Apple Silicon -- same fix already
  # documented from ShopSecure.
  docker pull --platform linux/amd64 "$src"
  docker tag "$src" "${ECR_REGISTRY}/${dest_repo}:latest"
  docker push "${ECR_REGISTRY}/${dest_repo}:latest"
}

# --- Istio (ambient mode) ---
mirror "docker.io/istio/pilot:${ISTIO_VERSION}"       "mirror/istio-pilot"
mirror "docker.io/istio/ztunnel:${ISTIO_VERSION}"     "mirror/istio-ztunnel"
mirror "docker.io/istio/install-cni:${ISTIO_VERSION}" "mirror/istio-install-cni"
mirror "docker.io/istio/proxyv2:${ISTIO_VERSION}"     "mirror/istio-proxyv2"

# --- SPIRE (not deployed until Phase 3 -- comment out to defer) ---
mirror "ghcr.io/spiffe/spire-server:${SPIRE_VERSION}" "mirror/spire-server"
mirror "ghcr.io/spiffe/spire-agent:${SPIRE_VERSION}"  "mirror/spire-agent"

echo ""
echo "Done. Spot-check with:"
echo "  aws ecr describe-images --repository-name mirror/istio-pilot --region ${AWS_REGION}"
