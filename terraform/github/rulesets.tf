locals {
  # Required checks are the workflow jobs that run on every pull request.
  # Path-filtered jobs (K3s "TCO and OpenCost pricing") would block the pull
  # requests they skip, so they stay out.
  platform_repositories = {
    K3s = {
      private = false
      checks  = ["Kustomize build and validate", "trivy"]
    }
    CMP = {
      private = false
      checks  = ["test-backend", "test-frontend", "docker-build-test", "a11y", "trivy"]
    }
    cnp-projects = {
      private = false
      checks  = ["validate", "trivy"]
    }
    cnp-project-base = {
      private = false
      checks  = ["trivy"]
    }
    app-templates = {
      private = false
      checks  = ["trivy"]
    }
    cnp-docs = {
      private = false
      checks  = ["trivy"]
    }
    Cloud = {
      private = true
      checks  = ["trivy"]
    }
  }

  ruleset_repositories = {
    for name, repo in local.platform_repositories : name => repo
    if !repo.private || var.manage_private_repositories
  }

  # The CMP writes the project registry straight to main of cnp-projects
  # (API commits, signed by GitHub). Nothing else pushes to main.
  direct_push_apps = {
    cnp-projects = [var.cnp_portal_app_id]
  }

  github_actions_app_id = 15368
}

resource "github_repository_ruleset" "main" {
  for_each    = local.ruleset_repositories
  name        = "main-reviewed"
  repository  = each.key
  target      = "branch"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  dynamic "bypass_actors" {
    for_each = lookup(local.direct_push_apps, each.key, [])
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }

  dynamic "bypass_actors" {
    for_each = var.org_admin_pull_request_bypass ? [1] : []
    content {
      actor_id    = 1
      actor_type  = "OrganizationAdmin"
      bypass_mode = "pull_request"
    }
  }

  rules {
    deletion            = true
    non_fast_forward    = true
    required_signatures = var.require_signed_commits

    pull_request {
      required_approving_review_count   = 1
      require_code_owner_review         = true
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }

    required_status_checks {
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = each.value.checks
        content {
          context        = required_check.value
          integration_id = local.github_actions_app_id
        }
      }
    }
  }
}
