# openshell-enclawed-sandbox

Sandbox image for running [Enclawed](https://github.com/enclawed/enclawed-oss) inside [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell).

Companion to the OpenShell PR that registers `enclawed` as an agent provider (`providers/enclawed.yaml`, `crates/openshell-providers/src/providers/enclawed.rs`). Plays the same role that [NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw) plays for OpenClaw: a thin partner-owned sandbox image OpenShell pulls when the operator runs

```
openshell sandbox create --from enclawed-sandbox
```

## What's Enclawed?

A classification-gated AI agent gateway with an MCP-attested transport layer ([arXiv:2605.24248](https://arxiv.org/abs/2605.24248)). Composes admission control, tool-level authorization, and a hash-chained audit log around standard MCP servers. Bundled apps: `secretary` (Gmail / CalDAV / CardDAV automation) and `codex` (hardened coding agent).

## Layout

- `Dockerfile` — two-stage build. Stage 1 clones `enclawed/enclawed-oss` at the pinned ref and runs `pnpm install --frozen-lockfile`. Stage 2 is a slim runtime layer that installs `libsecret-tools` (the keyring backend Enclawed writes to), creates a non-root `operator` user, and exposes the enclawed CLI at `/usr/local/bin/enclawed` — the path OpenShell's provider yaml declares.
- `entrypoint.sh` — runs Enclawed's installer on first boot to populate the sandbox-internal keyring from whatever credentials OpenShell injected as env vars at sandbox-create time, then execs into the operator's CMD.

## Build

```
docker build --build-arg ENCLAWED_REF=main -t enclawed-sandbox:dev .
```

`ENCLAWED_REF` defaults to `main`; pin a tag for reproducibility.

## Status

v0 scaffold. Tracking work:

- [ ] Two-stage Dockerfile with a cached base image (mirror NemoClaw's `Dockerfile.base` + GHCR cache pattern).
- [ ] Sandbox manifest (`sandbox.yaml`) for OpenShell's catalog if/when that schema is published upstream.
- [ ] CI: build the image on every push to `main`, publish to `ghcr.io/enclawed/openshell-enclawed-sandbox`.
- [ ] Conformance run against the OpenShell sandbox harness once the upstream PR lands.

## License

Apache-2.0. See `LICENSE`.
