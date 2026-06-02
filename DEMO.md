# End-to-end demo evidence

Captured 2026-06-02 from a real OpenShell gateway built from
`enclawed/OpenShell:feat/enclawed-provider` (current commit at the time
of this run: `4449d35`), driven by `e2e/with-docker-gateway.sh` against
the sandbox image built from this repo (`enclawed-sandbox:demo`).

## Step 1 — Sandbox image builds and the CLI is reachable inside

```
$ docker build --build-arg ENCLAWED_REF=main -t enclawed-sandbox:demo .
[...]
Successfully tagged enclawed-sandbox:demo

$ docker run --rm --entrypoint /bin/bash enclawed-sandbox:demo -c 'enclawed --version'
[workspace-dir] using /opt/enclawed/.enclawed (new install — defaulting to ~/.enclawed/)
enclawed 1.0.1 (779319a)
```

## Step 2 — OpenShell workspace tests pass with the Enclawed provider in the registry

```
$ cargo test --workspace
[...]
workspace: 1926 passed, 0 failed across 23 test blocks
```

(Including two new tests added by the PR:
`profiles::tests::enclawed_profile_is_an_agent_with_no_credential_discovery_and_default_backend_endpoints`
and
`providers::enclawed::tests::enclawed_provider_discovery_is_empty_by_default`.)

## Step 3 — Live gateway returns the Enclawed profile via real gRPC

```
$ OPENSHELL_E2E_DOCKER_SANDBOX_IMAGE=enclawed-sandbox:demo \
    ./e2e/with-docker-gateway.sh \
    ./target/release/openshell provider list-profiles -o json
[...]
```

The gateway emits (excerpted from the JSON list):

```json
{
  "id": "enclawed",
  "display_name": "Enclawed",
  "description": "Classification-gated AI agent gateway with MCP-attested transport (enclawed-oss)",
  "category": "agent",
  "credentials": [],
  "endpoints": [
    {
      "host": "api.anthropic.com",
      "port": 443,
      "protocol": "rest",
      "access": "read-write",
      "enforcement": "enforce"
    },
    {
      "host": "127.0.0.1",
      "port": 11434,
      "protocol": "rest",
      "access": "read-write",
      "enforcement": "enforce"
    }
  ],
  "binaries": [
    "/usr/bin/enclawed",
    "/usr/local/bin/enclawed"
  ],
  "inference_capable": true
}
```

— exactly the shape declared in `providers/enclawed.yaml` on the
OpenShell PR. Category is `agent`, credential discovery is empty
(operator-keyring bootstrap), both default backends are enforced.

## Reproducing

```
git clone --branch feat/enclawed-provider https://github.com/enclawed/OpenShell.git ~/openshell
git clone https://github.com/enclawed/openshell-enclawed-sandbox.git ~/openshell-enclawed-sandbox
OPENSHELL_DIR=~/openshell ~/openshell-enclawed-sandbox/demo.sh
```
