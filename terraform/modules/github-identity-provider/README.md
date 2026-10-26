# GitHub account linking for CNP

This module manages only the `github` identity provider in an existing realm.
The root K3s Terraform configuration calls it through `github_identity_provider.tf`.
Its provider version is the existing root pin, `keycloak/keycloak` 5.9.0.

The root flag `github_identity_provider_enabled` defaults to false. Enabling it
requires a GitHub **OAuth** client ID and secret. The App installation ID, App RSA
private key and CNP OpenID client secret are different credentials.

The broker is account-linking only and hidden from the login page. It neither
creates realms/users nor changes authentication flows, roles or existing OIDC
clients. Email trust and token storage are disabled. `prevent_destroy` blocks
accidental removal after activation; deletion requires an explicit reviewed change.

The GitHub OAuth application must allow the module's exact `callback_url`. For a
GitHub App, ensure user **Email addresses: read** is enabled; classic OAuth apps
use the `user:email` scope. The public callback origin is independent of the
Keycloak administration URL.

Run isolated checks without the shared S3 backend:

```sh
terraform -chdir=terraform/modules/github-identity-provider init -backend=false
terraform -chdir=terraform/modules/github-identity-provider validate
terraform -chdir=terraform/modules/github-identity-provider test
```

These native tests use a mocked Keycloak provider. No real realm, user or broker
is created. Apply belongs to the **root K3s state**, not this test directory.

The activation procedure is in `k8s/config/keycloak/GITHUB_IDENTITY_PROVIDER.md`.
It requires the team's normal root Terraform variables and backend access. The
plan guard `scripts/check_github_identity_plan.py` rejects unrelated changes,
deletions, drift and a broker outside the approved account-linking contract.

Provider reference:
https://github.com/keycloak/terraform-provider-keycloak/blob/v5.9.0/docs/resources/oidc_github_identity_provider.md
