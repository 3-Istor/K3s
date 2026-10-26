variable "realm_id" {
  description = "Existing Keycloak realm; this module never creates a realm or user."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.realm_id))
    error_message = "Supply an existing realm identifier."
  }
}

variable "public_keycloak_url" {
  description = "Public HTTPS URL used by the GitHub OAuth callback, independently of the admin URL."
  type        = string
  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$", var.public_keycloak_url))
    error_message = "Supply the public HTTPS Keycloak origin without a path."
  }
}

variable "client_id" {
  description = "OAuth client ID of the approved GitHub App, not its installation ID."
  type        = string
  validation {
    condition     = length(trimspace(var.client_id)) > 0
    error_message = "The GitHub OAuth client ID is required."
  }
}

variable "client_secret" {
  description = "GitHub OAuth client secret, not the App private key or the CNP OIDC client secret."
  type        = string
  sensitive   = true
  validation {
    condition     = length(trimspace(var.client_secret)) > 0
    error_message = "The GitHub OAuth client secret is required."
  }
}
