terraform {
  # Its own state: the token here is an org owner's, kept apart from the Vault
  # and Keycloak credentials of terraform/.
  backend "s3" {
    bucket       = "istor-cnp-tfstate-757826"
    key          = "cnp/github/terraform.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
    encrypt      = true
    profile      = "3-istor"
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.12.1"
    }
  }
}

# Token from GITHUB_TOKEN (an org owner: `gh auth token` with admin:org).
provider "github" {
  owner = var.organization
}
