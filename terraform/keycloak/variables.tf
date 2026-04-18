variable "keycloak_url" {
  description = "The Base URL of the Keycloak instance"
  type        = string
}

variable "keycloak_username" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "base_domain" {
  description = "Base domain for the lab"
  type        = string
  default     = "3istor.com"
}
