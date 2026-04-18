terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.7.0"
    }
  }
}

provider "keycloak" {
  client_id                = "admin-cli"
  url                      = var.keycloak_url
  username                 = var.keycloak_username
  password                 = var.keycloak_password
  tls_insecure_skip_verify = true # Required for your self-signed cert-manager issuer
}
