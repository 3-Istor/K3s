output "demo_app_client_id" {
  value       = keycloak_openid_client.envoy_demo_app.client_id
  description = "Client ID for the Envoy Native OIDC"
}

output "demo_app_client_secret" {
  value       = keycloak_openid_client.envoy_demo_app.client_secret
  sensitive   = true
  description = "Client Secret for the Envoy Native OIDC"
}

output "argocd_client_secret" {
  value       = keycloak_openid_client.argocd.client_secret
  sensitive   = true
  description = "Client Secret for ArgoCD"
}

output "oidc_issuer_url" {
  value       = "${var.keycloak_url}/realms/${keycloak_realm.kube_lab.realm}"
  description = "The Issuer URL to put in your Envoy config"
}
