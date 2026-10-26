mock_provider "keycloak" {}

variables {
  realm_id            = "test-cnp"
  public_keycloak_url = "https://sso.example.org"
  client_id           = "test-oauth-client"
  client_secret       = "test-only-oauth-secret"
}

run "linking_does_not_enable_a_new_login_method" {
  command = plan
  assert {
    condition = (
      keycloak_oidc_github_identity_provider.github.enabled &&
      keycloak_oidc_github_identity_provider.github.link_only &&
      keycloak_oidc_github_identity_provider.github.hide_on_login_page &&
      !keycloak_oidc_github_identity_provider.github.trust_email &&
      !keycloak_oidc_github_identity_provider.github.store_token &&
      !keycloak_oidc_github_identity_provider.github.add_read_token_role_on_create
    )
    error_message = "GitHub must only link an existing authenticated account, without trusting email or retaining tokens."
  }
  assert {
    condition = (
      keycloak_oidc_github_identity_provider.github.alias == "github" &&
      keycloak_oidc_github_identity_provider.github.github_json_format &&
      keycloak_oidc_github_identity_provider.github.default_scopes == "user:email"
    )
    error_message = "The import protocol expects the github alias and identity-only OAuth scopes."
  }
  assert {
    condition = (
      output.callback_url == "https://sso.example.org/realms/test-cnp/broker/github/endpoint" &&
      output.account_link_url == "https://sso.example.org/realms/test-cnp/account/account-security/linked-accounts"
    )
    error_message = "Public URLs must use the selected realm and public origin."
  }
}

run "missing_oauth_client_id_blocks_the_plan" {
  command = plan
  variables { client_id = "" }
  expect_failures = [var.client_id]
}

run "missing_oauth_secret_blocks_the_plan" {
  command = plan
  variables { client_secret = "" }
  expect_failures = [var.client_secret]
}

run "unsafe_public_origin_blocks_the_plan" {
  command = plan
  variables { public_keycloak_url = "http://sso.example.org/path" }
  expect_failures = [var.public_keycloak_url]
}
