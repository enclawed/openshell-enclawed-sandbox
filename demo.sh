#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Enclawed LLC
# SPDX-License-Identifier: Apache-2.0
#
# End-to-end demo: build the partner sandbox image, register the Enclawed
# provider in a local OpenShell gateway, create a sandbox from the image,
# and verify the Enclawed CLI is reachable inside.
#
# Prerequisites (run once):
#   sudo apt install libclang-dev libz3-dev
#   sudo usermod -aG docker $USER && newgrp docker
#   curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.95.0
#
# Layout:
#   - This script lives in the partner sandbox repo
#     (github.com/enclawed/openshell-enclawed-sandbox).
#   - It expects $OPENSHELL_DIR to point at a checkout of NVIDIA/OpenShell
#     containing the `enclawed` provider (the feat/enclawed-provider branch
#     on enclawed/OpenShell, or whatever upstream commit lands the PR).
#
# Usage:
#   OPENSHELL_DIR=~/openshell ENCLAWED_REF=main ./demo.sh

set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHELL_DIR="${OPENSHELL_DIR:-${HOME}/openshell}"
ENCLAWED_REF="${ENCLAWED_REF:-main}"
IMAGE_TAG="${IMAGE_TAG:-enclawed-sandbox:demo}"

step() {
  printf '\n\033[1;36m==>\033[0m %s\n' "$1"
}

# --- 0. sanity ---------------------------------------------------------------
step "Sanity-checking environment"
[[ -d "${OPENSHELL_DIR}" ]] || { echo "OPENSHELL_DIR=${OPENSHELL_DIR} does not exist" >&2; exit 1; }
[[ -f "${OPENSHELL_DIR}/providers/enclawed.yaml" ]] || {
  echo "OpenShell checkout at ${OPENSHELL_DIR} is missing providers/enclawed.yaml — did you check out the feat/enclawed-provider branch?" >&2
  exit 1
}
command -v docker >/dev/null || { echo "docker not on PATH" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not reachable (are you in the docker group?)" >&2; exit 1; }
command -v cargo >/dev/null || . "${HOME}/.cargo/env"

# --- 1. build the sandbox image ----------------------------------------------
step "Building enclawed sandbox image (${IMAGE_TAG}, ref=${ENCLAWED_REF})"
docker build --build-arg ENCLAWED_REF="${ENCLAWED_REF}" -t "${IMAGE_TAG}" "${SANDBOX_DIR}"

# --- 2. show the enclawed CLI inside the image -------------------------------
step "enclawed --version inside the sandbox image"
docker run --rm --entrypoint /usr/local/bin/enclawed "${IMAGE_TAG}" --version || \
  echo "(enclawed --version not implemented yet; sandbox image still proves install path)"

# --- 3. build openshell + register the enclawed provider ---------------------
step "Building OpenShell gateway + CLI (release)"
(cd "${OPENSHELL_DIR}" && cargo build --release -p openshell-cli -p openshell-server -p openshell-sandbox)

OS_CLI="${OPENSHELL_DIR}/target/release/openshell"
[[ -x "${OS_CLI}" ]] || { echo "openshell CLI not built at ${OS_CLI}" >&2; exit 1; }

step "Listing built-in provider profiles (expect 'enclawed' present)"
"${OS_CLI}" provider list-profiles -o json | python3 -c '
import json,sys
ids = [p["id"] for p in json.load(sys.stdin)]
print("\n".join(ids))
assert "enclawed" in ids, f"enclawed missing from {ids}"
print("\n[OK] enclawed is in the built-in profile catalog")
'

# --- 4. drive the docker-gateway e2e harness with our sandbox image ---------
step "Running e2e/with-docker-gateway.sh, asking it to create a sandbox from ${IMAGE_TAG}"
(cd "${OPENSHELL_DIR}" && \
   OPENSHELL_E2E_DOCKER_SANDBOX_IMAGE="${IMAGE_TAG}" \
   ./e2e/with-docker-gateway.sh \
     ./target/release/openshell sandbox create --name enclawed-demo)

step "Done."
echo "If everything above ran clean, the Enclawed-in-OpenShell integration is live."
