# This resource writes every setting it knows, so the ones not being changed
# are spelled out with their values of 2026-11-11 instead of the provider's
# defaults. Two-factor enforcement has no API: see README.
resource "github_organization_settings" "this" {
  billing_email = var.billing_email
  location      = "France"

  default_repository_permission = "read"

  members_can_create_repositories          = false
  members_can_create_public_repositories   = false
  members_can_create_private_repositories  = false
  members_can_create_internal_repositories = false
  members_can_fork_private_repositories    = false

  members_can_create_pages         = true
  members_can_create_public_pages  = true
  members_can_create_private_pages = true

  has_organization_projects   = true
  has_repository_projects     = true
  web_commit_signoff_required = false

  advanced_security_enabled_for_new_repositories               = false
  dependabot_alerts_enabled_for_new_repositories               = false
  dependabot_security_updates_enabled_for_new_repositories     = false
  dependency_graph_enabled_for_new_repositories                = false
  secret_scanning_enabled_for_new_repositories                 = false
  secret_scanning_push_protection_enabled_for_new_repositories = false
}
