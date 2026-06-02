# openshell-enclawed-sandbox

**Deployment repo** for running [Enclawed](https://github.com/enclawed/enclawed-oss) inside [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) — provider profile + sandbox image + install path.

Ships entirely on the **Providers v2** path (see [providers-v2 docs](https://github.com/NVIDIA/OpenShell/blob/main/docs/sandboxes/providers-v2.mdx)), so no upstream OpenShell code change is required. The operator imports a profile + uses the sandbox image; OpenShell loads everything at runtime.

## What's Enclawed?

A classification-gated AI agent gateway with an MCP-attested transport layer ([arXiv:2605.24248](https://arxiv.org/abs/2605.24248)). Composes admission control + tool-level authorization + a hash-chained audit log around standard MCP servers. Bundled apps: `secretary` (Gmail / CalDAV / CardDAV automation) and `codex` (hardened coding agent).

## Repo contents

| File | Role |
|---|---|
| `enclawed.yaml` | The Providers v2 profile. Operator imports via `openshell provider profile import -f enclawed.yaml`. |
| `Dockerfile` | Sandbox image. Two-stage: clones `enclawed/enclawed-oss` at `ENCLAWED_REF`, runs `pnpm install --frozen-lockfile`, slim runtime with `libsecret-tools` (keyring backend), non-root `sandbox` user, `/usr/local/bin/enclawed` reachable. |
| `entrypoint.sh` | First-boot hook. Runs Enclawed's installer in non-interactive mode to populate the sandbox-internal keyring from whatever credentials OpenShell injected as env vars at sandbox-create time. |
| `demo.sh` | End-to-end runner: enables v2, imports the profile, creates a provider instance, lists. |
| `v2-validation.txt` | Captured transcript from a real run against upstream OpenShell `main` (commit `f061b1d`). |
| `LICENSE` | Apache-2.0 (matches OpenShell ecosystem convention; enclawed-oss core is MIT). |

## Quick start (operator)

```bash
# 1. One-time: enable Providers v2 on the active gateway.
openshell settings set --global --key providers_v2_enabled --value true --yes

# 2. Import the Enclawed profile.
openshell provider profile import -f enclawed.yaml

# 3. Build (or pull) the sandbox image.
docker build --build-arg ENCLAWED_REF=main -t enclawed-sandbox:latest .

# 4. Create a provider instance.
#    Note: a sentinel --credential is required by the current CLI even though
#    Enclawed itself bootstraps every secret via the OS keyring inside the
#    sandbox. The value is ignored by Enclawed at runtime.
openshell provider create --name my-enclawed --type enclawed \
  --credential ENCLAWED_BOOTSTRAP=keyring

# 5. Spin up a sandbox.
OPENSHELL_E2E_DOCKER_SANDBOX_IMAGE=enclawed-sandbox:latest \
  openshell sandbox create --name my-enclawed-sb
```

## Validation status

The end-to-end flow above was validated against unmodified OpenShell `main` (`f061b1d`) using `e2e/with-docker-gateway.sh`. See `v2-validation.txt` for the captured transcript and `demo.sh` for the reproducer.

## Open question for upstream

`openshell provider create` requires one of `--from-existing | --credential | --from-gcloud-adc`. For a deliberately credential-less profile (`credentials: []`) like Enclawed's — credentials live in the sandbox-internal OS keyring, not the gateway-managed credential store — neither `--from-existing` nor `--from-gcloud-adc` applies and the workaround is the sentinel `--credential ENCLAWED_BOOTSTRAP=keyring`. A future flag (`--no-credentials`) or implicit zero-credential path would make this cleaner; tracked as a feedback item, not a blocker.

## License

Apache-2.0. See `LICENSE`.
