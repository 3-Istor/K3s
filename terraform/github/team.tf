resource "github_team" "infra" {
  name        = "infra"
  description = "Platform owners: reviews every change to the CNP platform repositories."
  privacy     = "closed"
}

resource "github_team_members" "infra" {
  count   = length(var.infra_team_maintainers) > 0 ? 1 : 0
  team_id = github_team.infra.id

  dynamic "members" {
    for_each = var.infra_team_maintainers
    content {
      username = members.value
      role     = "maintainer"
    }
  }
}

# CODEOWNERS only counts a team with write access to the repository.
resource "github_team_repository" "infra" {
  for_each   = local.platform_repositories
  team_id    = github_team.infra.id
  repository = each.key
  permission = "push"
}
