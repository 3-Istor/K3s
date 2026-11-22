# AI runtime images

Images of the CNP AI landing zone agent runtime, deployed from `k8s/config/ai-tools` and
`k8s/config/agent-sandbox`; infra-templates renders the sidecar into every agent.

| Image | Role |
|---|---|
| `ghcr.io/3-istor/cnp-gw-auth-proxy` | Sidecar of every kagent agent. Listens on `127.0.0.1:15001` and forwards model (`/v1/*`), MCP (`/mcp/*`) and A2A calls to the AI gateway with the agent's Keycloak `client_credentials` JWT, renewed 60 s before expiry. Sub-agent calls from kagent (`proxy.url` = the sidecar, header `x-kagent-host: <agent>.<project>-<agent>`) go to `/a2a/<project>/<agent>`; agent cards are rewritten to point back at the sidecar, so A2A never goes pod to pod. |
| `ghcr.io/3-istor/cnp-run-python` | MCP server of the `run_python` tool (code mode). Per call: token exchange of the caller's JWT (client `sandbox-runner`, scope `mcp-read`, 300 s), one agent-sandbox `SandboxClaim` (`python` on gVisor, `python-kata` when the agent's namespace is `cnp.3istor.com/isolation=kata`), run, artifacts to the `ai-artifacts` bucket, served on `GET /ai-artifacts/<task>/<name>` for 24 h. |
| `ghcr.io/3-istor/cnp-sandbox-python` | Sandbox image: Python 3.13, numpy, pandas, matplotlib, the exec server and `cnp_tools`. `from cnp_tools import tools; tools.<server>.<tool>(**args)` is generated from the gateway's MCP tool list. |

## Configuration

gw-auth-proxy: `GW_CLIENT_ID`, `GW_CLIENT_SECRET` (required), `GW_TOKEN_URL`, `GW_UPSTREAM`, `GW_LISTEN`.
Probe: `exec ["/gw-auth-proxy", "healthcheck"]`.

run-python: `RUNNER_CLIENT_SECRET`, the ObjectBucketClaim ConfigMap and Secret (`BUCKET_HOST`, `BUCKET_PORT`,
`BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), optional `SANDBOX_NAMESPACE` (`ai-sandbox`),
`SANDBOX_TEMPLATE_GVISOR` (`python`), `SANDBOX_TEMPLATE_KATA` (`python-kata`), `TOKEN_URL`, `GATEWAY_URL`.

## Release

Tag `ai-runtime/vX.Y.Z` on main (workflow `.github/workflows/ai-runtime.yml`): the three images are built,
pushed as `X.Y.Z`, signed with cosign keyless and carry a CycloneDX SBOM attestation.

```bash
cosign verify ghcr.io/3-istor/cnp-gw-auth-proxy:0.1.0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/3-Istor/K3s/\.github/workflows/ai-runtime\.yml@refs/tags/ai-runtime/v'
```

## Tests

```bash
go test -race ./...
python -m unittest discover -s sandbox-image/tests
```
