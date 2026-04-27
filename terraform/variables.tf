# -----------------------------------------------------------------------------
# Keycloak Variables
# -----------------------------------------------------------------------------

variable "keycloak_url" {
  description = "The Base URL of the Keycloak instance"
  type        = string
  default     = "https://auth.3istor.com"
  # default = "http://localhost:8085"
}

variable "keycloak_admin_username" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "base_domain" {
  description = "Base domain for the lab"
  type        = string
  default     = "3istor.com"
}

# -----------------------------------------------------------------------------
# Kubernetes Variables
# -----------------------------------------------------------------------------

variable "k8s_host_url" {
  description = "The internal Kubernetes API server URL."
  type        = string
  default     = "https://kubernetes.default.svc.cluster.local"
}

# -----------------------------------------------------------------------------
# Vault Variables
# -----------------------------------------------------------------------------

variable "vault_url" {
  description = "The URL of the Vault server."
  type        = string
  default     = "https://vault.3istor.com"
  # default = "http://localhost:8200"
}

variable "vault_token" {
  description = "The token for accessing the Vault server."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# DNS Variables
# -----------------------------------------------------------------------------

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone Id of 3istor Record"
  type        = string
  default     = "5984eff5179d6656a7c9e1b00c768d21"
}

variable "dc_ip" {
  description = "The public IP address of the homelab network."
  type        = string
  default     = "176.186.130.237"
}

variable "domain_name" {
  description = "The domain name for the 3istor Cluster."
  type        = string
  default     = "3istor.com"
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}
