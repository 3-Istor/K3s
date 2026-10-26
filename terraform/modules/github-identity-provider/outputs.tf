output "callback_url" {
  description = "Register this exact callback URL in the GitHub App settings before activation."
  value       = "${trimsuffix(var.public_keycloak_url, "/")}/realms/${var.realm_id}/broker/github/endpoint"
}

output "account_link_url" {
  description = "Set GITHUB_ACCOUNT_LINK_URL in CMP only after the real account-linking flow is verified."
  value       = "${trimsuffix(var.public_keycloak_url, "/")}/realms/${var.realm_id}/account/account-security/linked-accounts"
}
