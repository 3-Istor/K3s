variable "organization" {
  type    = string
  default = "3-Istor"
}

variable "billing_email" {
  description = "Required by github_organization_settings; set it to the current one (Settings > Billing)."
  type        = string
}

variable "infra_team_maintainers" {
  description = "GitHub logins of the infra team, kept in an untracked tfvars file."
  type        = set(string)
  default     = []
}

variable "ruleset_enforcement" {
  description = "disabled until the infra team exists and the CODEOWNERS files are merged, then active."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "active"], var.ruleset_enforcement)
    error_message = "disabled or active (evaluate needs GitHub Enterprise)."
  }
}

variable "require_signed_commits" {
  description = "Refuses unsigned commits on main. Rebase merges are then impossible and every author needs a signing key."
  type        = bool
  default     = false
}

variable "manage_private_repositories" {
  description = "Rulesets on private repositories (Cloud) answer 403 on the Free plan."
  type        = bool
  default     = false
}

variable "org_admin_pull_request_bypass" {
  description = "Lets org owners merge a pull request without the approval (never a direct push). Break-glass only."
  type        = bool
  default     = false
}

variable "cnp_portal_app_id" {
  description = "App ID of the cnp-portal GitHub App, which the CMP commits to cnp-projects with."
  type        = number
  default     = 3836905
}
