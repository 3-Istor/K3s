# Keycloak client credentials of the AI platform clients (sandbox-runner, smoke).
path "${mount_path}/data/platform/ai-clients/*" {
  capabilities = ["read"]
}
