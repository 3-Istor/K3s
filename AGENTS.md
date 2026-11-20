# Agent instructions (Claude Code, Codex, …)

Write everything that lands in this repo in English: manifests, comments,
commits, PR titles and descriptions.

## Jira: before, during, after

Work is tracked in Jira, project **CNP** on `3istors.atlassian.net`. Use the
Atlassian MCP server. If it is not connected, tell the human instead of skipping
these steps.

**Before coding**
- Find the ticket for the work: the one the human names, otherwise a JQL search
  on the keywords (`project = CNP AND text ~ "..."`).
- Read the ticket, its comments and its linked PRs. If someone already started,
  or another ticket touches the same files, say so before writing code.
- No ticket: offer to create one. Do not work outside a ticket.

**During**
- Put the key in the branch and the PR title: `feat/cnp-110-cloud-observability`,
  `CNP-110: …` or `feat(observability): … (CNP-110)`.
- Comment on the ticket for each decision, finding that matters to others,
  blocker or opened PR. Short, factual, with links. What the team needs to know
  goes in Jira, not only in the conversation.

**After**
- PR merged: a summary comment (what shipped, what is left) and the status
  updated.
- Remaining work becomes sub-tickets, not a list in a comment.

Never change the status, assignee or description of a ticket that is not yours
unless the human asks. Never delete anything in Jira.

## This repo

- Argo CD tracks `main`: merging is deploying to production.
- CI builds every `kustomization.yaml` with Argo CD's flags
  (`kubectl kustomize --enable-helm --load-restrictor LoadRestrictionsNone`), then
  runs kubeconform. Run the same on the folder you changed before pushing.
- `terraform/` manages Keycloak, Vault and Cloudflare. Its state is local and not
  versioned: never run `plan` or `apply`, the human does. `terraform fmt` and
  `validate` are enough to check.
- No secrets in Git: everything goes through Vault and Vault Secrets Operator.
- Since CNP-110 the clouds write to the same VictoriaMetrics: filter every
  on-prem query on `cluster="onprem"`. Alloy's scrape of annotated pods renames
  the original `namespace` to `exported_namespace`.
- `finops/`: `go -C finops run ./tco` regenerates
  `k8s/config/opencost/values-pricing.yaml` from `finops/onprem-tco.yaml`; CI
  checks it with `-check`.
