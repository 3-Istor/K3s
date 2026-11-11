# GitHub organization: reviewed GitOps (CNP-124, W5)

The `3-Istor` organization as code: the `infra` team, a ruleset on `main` of
every platform repository, and the organization defaults.

It is its own root, not part of `terraform/`, because it runs with an org
owner's GitHub token and touches nothing in Vault, Keycloak or Cloudflare:
two roots, two blast radii, two states (`cnp/github/terraform.tfstate`).

## What it sets

| Resource | Effect |
|---|---|
| `github_team.infra` | Team `@3-Istor/infra`, owner of every path in the platform CODEOWNERS files. Members come from `infra_team_maintainers` in an untracked tfvars, never from Git. |
| `github_team_repository.infra` | `push` on the seven platform repositories. CODEOWNERS ignores a team without write access. |
| `github_repository_ruleset.main` | On the default branch: pull request required, 1 approval, code owner review, stale approvals dismissed on push, no force push, no deletion, required checks, signed commits behind `require_signed_commits` (default `false`). |
| `github_organization_settings.this` | `default_repository_permission = read`, members can no longer create repositories. Everything else keeps its value of 2026-11-11. |

Required checks per repository (the workflow jobs that run on every pull
request, source `github-actions`):

| Repository | Checks |
|---|---|
| K3s | `Kustomize build and validate`, `trivy` |
| CMP | `test-backend`, `test-frontend`, `docker-build-test`, `a11y`, `trivy` |
| cnp-projects | `validate`, `trivy` |
| cnp-project-base, app-templates, cnp-docs, Cloud | `trivy` |

K3s `TCO and OpenCost pricing` is left out: its workflow has path filters,
so a required check would wait forever on the pull requests it skips.

## Bots that write to main

| Bot | Today | Decision | Consequence |
|---|---|---|---|
| CMP (`cnp-portal` app) on cnp-projects | Commits the project registry straight to `main` through the API | Bypass, mode `always`, for this app on cnp-projects only | The CMP can still change any file of cnp-projects without review. The `validate` workflow on push and the CMP's own name checks are what stand behind it. |
| Argo CD Image Updater (`cnp-portal` creds) on K3s | `3istor-sessions` pushed to `main`; the others already open pull requests | `3istor-sessions` switched to pull requests in the same change | A new sessions image needs one approval before it ships, like mepa-app, qcm, linmap-bot and offhours-guard. |
| Image Updater on app repositories | Pushes to `main` of each project app repository | Out of scope: those repositories get no ruleset here | None. |
| Renovate (K3s, Cloud, app-templates) | Pull requests, no automerge | No bypass | Unchanged. |
| Dependabot + `dependabot-automerge.yml` (CMP) | `gh pr merge --auto` on patch and minor bumps | No bypass | Auto-merge now waits for one approval. Bypassing it would mean bypassing for the GitHub Actions app, i.e. for every workflow. |
| Humans pushing to `main` | Happens today (unsigned, unreviewed commits on K3s, CMP) | No bypass; `org_admin_pull_request_bypass` exists for break-glass | Every change goes through a pull request; the author cannot approve their own. |

CMP already has classic branch protection (four required checks, no review).
It stacks with the ruleset; remove it once the ruleset is active so there is
one place to read.

## Private repositories on the Free plan

Cloud is private and the organization is on GitHub Free: the rulesets and
branch protection APIs answer 403 there. `manage_private_repositories`
(default `false`) keeps Cloud out of the rulesets; the team access and its
CODEOWNERS file still apply, they are just not enforced. Options:

1. GitHub Team plan (paid per seat): rulesets on private repositories,
   then `manage_private_repositories = true`.
2. Make Cloud public after a full-history secret scan
   (`gitleaks detect --log-opts="--all"`) and a review of the Terraform
   variables and README examples, then set `private = false` for Cloud in
   `rulesets.tf` and apply.
3. Accept: Cloud is reviewed by convention only. Its changes are also the
   least frequent and are applied by hand with `terraform apply`.

## Apply order

1. `export GITHUB_TOKEN=$(gh auth token)` with an org owner who has the
   `admin:org` scope (`gh auth refresh -s admin:org`).
2. Write `github.auto.tfvars` (ignored by Git) with `billing_email` and
   `infra_team_maintainers`.
3. `terraform init && terraform apply`: creates the team and its access,
   rulesets in `disabled`, the org settings.
4. Merge the CODEOWNERS pull requests of the seven repositories.
5. Set `ruleset_enforcement = "active"` and apply.
6. Later, when every author signs: `require_signed_commits = true`.

`default_repository_permission = read` removes write access from every
member on every repository they do not reach through a team or as an outside
collaborator. Before step 3, give the student project repositories (IoT,
MEPA, qcm, NLPF and the others) a team or a collaborator with write, or
apply with the old value first.

## Done in the console, not here

- Require two-factor authentication: Settings > Authentication security >
  "Require two-factor authentication". There is no API for it on the Free
  plan; members without 2FA are removed from the organization, so check
  `gh api orgs/3-Istor/members?filter=2fa_disabled` first.
- The `cnp-portal` GitHub App permissions stay as they are; the bypass only
  works while it keeps `contents: write` on cnp-projects.

## Rollback

`ruleset_enforcement = "disabled"` and apply turns every ruleset off without
losing them. `terraform destroy -target=github_repository_ruleset.main`
removes them. The org settings revert by setting the old values
(`default_repository_permission = "write"`, the `members_can_create_*`
to `true`).
