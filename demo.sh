#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Enclawed LLC
# SPDX-License-Identifier: Apache-2.0
#
# End-to-end demo of the Enclawed-in-OpenShell integration via Providers v2.
# No upstream OpenShell code change required; ships entirely as a deployment
# repo (this file lives in github.com/enclawed/openshell-enclawed-sandbox).
#
# Prerequisites:
#   sudo apt install libclang-dev libz3-dev
#   sudo usermod -aG docker $USER && newgrp docker
#   curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.95.0
#
# Layout:
#   - $OPENSHELL_DIR points at a checkout of NVIDIA/OpenShell (default
#     ~/openshell). Required for the e2e harness that brings up a real
#     gateway with the Docker compute driver.
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

# --- 0. sanity --------------------------------------------------------------
step "Sanity-checking environment"
[[ -d "${OPENSHELL_DIR}" ]] || { echo "OPENSHELL_DIR=${OPENSHELL_DIR} does not exist" >&2; exit 1; }
[[ -f "${SANDBOX_DIR}/enclawed.yaml" ]] || { echo "missing ${SANDBOX_DIR}/enclawed.yaml" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not on PATH" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not reachable (are you in the docker group?)" >&2; exit 1; }
command -v cargo >/dev/null || . "${HOME}/.cargo/env"

# --- 1. build the sandbox image --------------------------------------------
step "Building enclawed sandbox image (${IMAGE_TAG}, ref=${ENCLAWED_REF})"
docker build --build-arg ENCLAWED_REF="${ENCLAWED_REF}" -t "${IMAGE_TAG}" "${SANDBOX_DIR}"

# --- 2. show enclawed CLI inside the image ---------------------------------
step "enclawed --version inside the sandbox image"
docker run --rm --entrypoint /usr/local/bin/enclawed "${IMAGE_TAG}" --version

# --- 3. build OpenShell binaries -------------------------------------------
step "Building OpenShell gateway + CLI + sandbox supervisor (release)"
(cd "${OPENSHELL_DIR}" && cargo build --release -p openshell-cli -p openshell-server -p openshell-sandbox)

# --- 4. drive the v2 roundtrip through the docker-gateway e2e harness ------
step "Providers v2 roundtrip: enable, import, list-profiles, create, list"
cat > /tmp/v2chain.sh <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
OS=__OS__
PY=/usr/bin/python3
echo "== STEP 1 enable v2 =="
"$OS" settings set --global --key providers_v2_enabled --value true --yes
echo "== STEP 2 import enclawed profile =="
"$OS" provider profile import -f __SANDBOX__/enclawed.yaml
echo "== STEP 3 list-profiles =="
"$OS" provider list-profiles -o json > /tmp/v2-profiles.json
"$PY" -c "import json; profs=json.load(open('/tmp/v2-profiles.json')); ids=[p['id'] for p in profs]; assert 'enclawed' in ids, ids; e=next(p for p in profs if p['id']=='enclawed'); print('[OK] enclawed in profile list; category=', e.get('category'), '; credentials=', e.get('credentials'), '; endpoints=', len(e.get('endpoints', [])))"
echo "== STEP 4 create provider instance (sentinel credential — keyring is owned by enclawed installer inside the sandbox) =="
"$OS" provider create --name enclawed-demo --type enclawed --credential ENCLAWED_BOOTSTRAP=keyring
echo "== STEP 5 list provider instances =="
"$OS" provider list
echo "== ALL STEPS PASSED =="
INNER
sed -i "s|__OS__|${OPENSHELL_DIR}/target/release/openshell|g; s|__SANDBOX__|${SANDBOX_DIR}|g" /tmp/v2chain.sh
chmod +x /tmp/v2chain.sh

(cd "${OPENSHELL_DIR}" && \
   OPENSHELL_E2E_DOCKER_SANDBOX_IMAGE="${IMAGE_TAG}" \
   ./e2e/with-docker-gateway.sh /tmp/v2chain.sh)

step "Done."
echo "If everything above ran clean, the Enclawed-in-OpenShell integration is live on the Providers v2 path with zero code change to OpenShell."
