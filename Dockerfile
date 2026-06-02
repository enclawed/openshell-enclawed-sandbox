# SPDX-FileCopyrightText: Copyright (c) 2026 Enclawed LLC
# SPDX-License-Identifier: Apache-2.0
#
# Sandbox image for running Enclawed inside NVIDIA OpenShell.
#
# Companion to the OpenShell PR that adds the `enclawed` agent provider.
# Mirrors the layout of NVIDIA/NemoClaw (the sandbox repo behind the
# OpenClaw entry in OpenShell's Supported Agents table): a thin
# partner-owned image that OpenShell pulls when the operator runs
#   openshell sandbox create --from enclawed-sandbox
#
# This is a v0 scaffold: it installs the enclawed-oss source tree and
# its workspace dependencies, then defers to an entrypoint that runs
# enclawed's own installer at first boot so the operator's keyring is
# populated inside the sandbox.

ARG NODE_VERSION=24.15.0
ARG ENCLAWED_REF=main

# ---- builder stage: clone + pnpm install -------------------------------
FROM node:${NODE_VERSION}-trixie-slim AS builder

ENV NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH

# git: clone enclawed-oss at the pinned ref
# ca-certificates: TLS for npm + Anthropic / Ollama endpoints
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pin pnpm to the version enclawed-oss expects.
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate

ARG ENCLAWED_REF
WORKDIR /opt
RUN git clone --depth=1 --branch ${ENCLAWED_REF} \
      https://github.com/enclawed/enclawed-oss.git enclawed
WORKDIR /opt/enclawed
RUN pnpm install --prefer-offline --ignore-scripts --frozen-lockfile

# ---- runtime stage ------------------------------------------------------
FROM node:${NODE_VERSION}-trixie-slim AS runtime

ENV NODE_ENV=production \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# libsecret backs the OS keyring on Linux. Enclawed's installer writes
# every credential here at first boot instead of into .env. The
# accompanying secret-tool CLI is what enclawed shells out to.
# tini: PID 1 + signal forwarding for clean shutdown.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates tini libsecret-tools \
    && rm -rf /var/lib/apt/lists/*

# Non-root operator. OpenShell's sandbox primitives expect a known
# uid:gid; 1000:1000 is the convention. Override via build arg if your
# sandbox manifest pins a different uid.
ARG OPERATOR_UID=1000
ARG OPERATOR_GID=1000
RUN groupadd -g ${OPERATOR_GID} operator \
    && useradd -m -u ${OPERATOR_UID} -g ${OPERATOR_GID} -s /bin/bash operator

# Pull the resolved tree from the builder. The pnpm symlink layout is
# preserved so the in-tree `node_modules/.bin/enclawed` shim works.
COPY --from=builder --chown=operator:operator /opt/enclawed /opt/enclawed

# Make the enclawed CLI reachable at the conventional path the
# OpenShell provider yaml declares (providers/enclawed.yaml `binaries`).
RUN ln -s /opt/enclawed/node_modules/.bin/enclawed /usr/local/bin/enclawed

COPY --chown=operator:operator entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER operator
WORKDIR /home/operator
ENV ENCLAWED_HOME=/opt/enclawed

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
