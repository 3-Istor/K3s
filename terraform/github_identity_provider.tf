# Disabled by default: publication of this branch cannot activate shared SSO.
module "github_account_linking" {
  count  = var.github_identity_provider_enabled ? 1 : 0
  source = "./modules/github-identity-provider"

  realm_id            = keycloak_realm.kube_lab.id
  public_keycloak_url = "https://auth.${var.base_domain}"
  client_id           = var.github_oauth_client_id
  client_secret       = var.github_oauth_client_secret
}

output "github_identity_provider_urls" {
  description = "Public callback/account URLs when the GitHub broker is explicitly enabled."
  value = var.github_identity_provider_enabled ? {
    callback_url     = module.github_account_linking[0].callback_url
    account_link_url = module.github_account_linking[0].account_link_url
  } : null
}
