# Keycloak Policy
path "${mount_path}/data/keycloak/*" {
  capabilities = ["read"]
}
