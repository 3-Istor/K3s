terraform {
  backend "s3" {
    bucket         = "3-istor-tf-infra-aws"
    key            = "infra/bare-metal/k3s-master/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    profile        = "3-istor"
  }

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.8.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "5.10.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.21.1"
    }
  }
}

provider "keycloak" {
  client_id                = "admin-cli"
  url                      = var.keycloak_url
  username                 = var.keycloak_admin_username
  password                 = var.keycloak_admin_password
  tls_insecure_skip_verify = false # Set to true if using self-signed certs
}

provider "vault" {
  address = var.vault_url
  # skip_tls_verify = false
  token = var.vault_token # Set in environment variable VAULT_TOKEN or ~/.vault-token file (if both are unset)
  # ca_cert_file = "" # Path to CA cert file if using self-signed certs
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token_secret_var
}
