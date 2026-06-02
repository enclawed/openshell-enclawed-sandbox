#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Enclawed LLC
# SPDX-License-Identifier: Apache-2.0
#
# Sandbox entrypoint. Runs once per `openshell sandbox create` and on
# every restart. Responsibilities:
#   1. On first boot, invoke enclawed's installer to populate the
#      sandbox-internal keyring (libsecret) from whatever credentials
#      OpenShell injected as environment variables at sandbox-create
#      time.
#   2. On every boot, exec into the operator's CMD (defaults to bash
#      so the operator can drop into the live enclawed workspace).

set -euo pipefail

ENCLAWED_HOME="${ENCLAWED_HOME:-/opt/enclawed}"
INIT_SENTINEL="${HOME}/.enclawed-sandbox-initialized"

if [[ ! -f "$INIT_SENTINEL" ]]; then
  echo "[enclawed-sandbox] first boot: running enclawed-apps installer to seed keyring"

  # The installer reads ENCLAWED_*  / ANTHROPIC_API_KEY / etc. from the
  # environment when running non-interactively. It then writes them to
  # libsecret via secret-tool and clears them from .env.
  if [[ -x "${ENCLAWED_HOME}/enclawed-apps/install.sh" ]]; then
    "${ENCLAWED_HOME}/enclawed-apps/install.sh" --non-interactive || {
      echo "[enclawed-sandbox] installer reported a non-zero exit; continuing" >&2
    }
  else
    echo "[enclawed-sandbox] no install.sh found at ${ENCLAWED_HOME}/enclawed-apps; skipping bootstrap" >&2
  fi

  touch "$INIT_SENTINEL"
fi

exec "$@"
