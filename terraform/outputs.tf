output "openid_client_id" {
  value       = keycloak_openid_client.openid_client.client_id
  description = "Client ID for the Envoy Native OIDC"
}

output "openid_client_secret" {
  value       = keycloak_openid_client.openid_client.client_secret
  sensitive   = true
  description = "Client Secret for the Envoy Native OIDC"
}

output "oidc_issuer_url" {
  value       = "${var.keycloak_url}/realms/${keycloak_realm.kube_lab.realm}"
  description = "The Issuer URL to put in your Envoy config"
}

# For the KeycloakElevatedGroupChangedOutsideCmp rule in
# k8s/config/observability/loki-security-rules.yaml: admin events name groups
# and actors by id only.
output "elevated_group_ids_regex" {
  value       = join("|", sort([for g in keycloak_group.elevated : g.id]))
  description = "Ids of the elevated-* groups, as a LogQL regex"
}

output "cmp_service_account_user_id" {
  value       = keycloak_openid_client.openid_client.service_account_user_id
  description = "Keycloak user id the CMP changes group memberships as"
}
