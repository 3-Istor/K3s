# -----------------------------------------------------------------------------
# AI gateway (AI landing zone): Keycloak identities and Vault access
# -----------------------------------------------------------------------------
# Tokens for the gateway carry aud=ai-gateway, azp (the calling client),
# project and, for the sandbox, agent. Agent and app clients
# (agent-<project>-<agent>, app-<project>-<app>) are created by the CMP through
# cmp-provisioner, not here: it gives them the default scope ai-gateway plus
# the mcp-read / mcp-write / web-search scopes the ProjectRecord grants, an
# access token lifespan of 300 s, and puts their service account user in
# ai-projects/<project>, whose attribute cnp_ai_project becomes the project
# claim.

resource "keycloak_openid_client" "ai_gateway" {
  realm_id    = keycloak_realm.kube_lab.id
  client_id   = "ai-gateway"
  name        = "AI gateway (audience)"
  enabled     = true
  access_type = "BEARER-ONLY"
}

resource "keycloak_group" "ai_projects" {
  realm_id = keycloak_realm.kube_lab.id
  name     = "ai-projects"
}

resource "keycloak_openid_client_scope" "ai_gateway" {
  realm_id               = keycloak_realm.kube_lab.id
  name                   = "ai-gateway"
  description            = "Audience, project and agent claims read by the AI gateway"
  include_in_token_scope = false
}

resource "keycloak_openid_audience_protocol_mapper" "ai_gateway_audience" {
  realm_id                 = keycloak_realm.kube_lab.id
  client_scope_id          = keycloak_openid_client_scope.ai_gateway.id
  name                     = "audience-ai-gateway"
  included_client_audience = keycloak_openid_client.ai_gateway.client_id
  add_to_id_token          = false
  add_to_access_token      = true
}

# Keycloak resolves a user attribute through the user's groups when the user
# has none, so the service account inherits the attribute of its
# ai-projects/<project> group.
resource "keycloak_openid_user_attribute_protocol_mapper" "ai_gateway_project" {
  realm_id            = keycloak_realm.kube_lab.id
  client_scope_id     = keycloak_openid_client_scope.ai_gateway.id
  name                = "project"
  user_attribute      = "cnp_ai_project"
  claim_name          = "project"
  claim_value_type    = "String"
  add_to_id_token     = false
  add_to_access_token = true
  add_to_userinfo     = false
}

# In a token exchanged by sandbox-runner, azp is sandbox-runner and sub is the
# calling agent's service account. The username keeps the agent visible
# (service-account-agent-<project>-<agent>); the gateway strips the prefix.
resource "keycloak_openid_user_property_protocol_mapper" "ai_gateway_agent" {
  realm_id            = keycloak_realm.kube_lab.id
  client_scope_id     = keycloak_openid_client_scope.ai_gateway.id
  name                = "agent"
  user_property       = "username"
  claim_name          = "agent"
  add_to_id_token     = false
  add_to_access_token = true
  add_to_userinfo     = false
}

resource "keycloak_openid_client_scope" "ai_tool_scope" {
  for_each               = toset(["mcp-read", "mcp-write", "web-search"])
  realm_id               = keycloak_realm.kube_lab.id
  name                   = each.key
  description            = "AI gateway permission ${each.key}"
  include_in_token_scope = true
}

# -----------------------------------------------------------------------------
# sandbox-runner: run_python exchanges the calling agent's token for a
# read-only one (scope mcp-read, 300 s) that code in the sandbox uses.
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "sandbox_runner" {
  realm_id                        = keycloak_realm.kube_lab.id
  client_id                       = "sandbox-runner"
  name                            = "AI sandbox token exchange"
  enabled                         = true
  access_type                     = "CONFIDENTIAL"
  standard_flow_enabled           = false
  direct_access_grants_enabled    = false
  implicit_flow_enabled           = false
  service_accounts_enabled        = false
  standard_token_exchange_enabled = true
  access_token_lifespan           = "300"
  full_scope_allowed              = false
}

resource "keycloak_openid_client_default_scopes" "sandbox_runner" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = keycloak_openid_client.sandbox_runner.id
  default_scopes = [
    "basic",
    keycloak_openid_client_scope.ai_gateway.name,
  ]
}

resource "keycloak_openid_client_optional_scopes" "sandbox_runner" {
  realm_id  = keycloak_realm.kube_lab.id
  client_id = keycloak_openid_client.sandbox_runner.id
  optional_scopes = [
    keycloak_openid_client_scope.ai_tool_scope["mcp-read"].name,
  ]
}

# -----------------------------------------------------------------------------
# Platform clients of the gateway (project claim cnp-platform)
# -----------------------------------------------------------------------------
# cmp-ai: the CMP's own client (draft-agent on /v1/messages, test chat on
# /a2a/<p>/<a> for project members). ai-gateway-smoke: operator smoke tests
# and the end-to-end checks of the budget guard.
resource "keycloak_group" "ai_platform" {
  realm_id  = keycloak_realm.kube_lab.id
  parent_id = keycloak_group.ai_projects.id
  name      = "cnp-platform"
  attributes = {
    cnp_ai_project = "cnp-platform"
  }
}

resource "keycloak_openid_client" "ai_platform" {
  for_each                     = toset(["cmp-ai", "ai-gateway-smoke"])
  realm_id                     = keycloak_realm.kube_lab.id
  client_id                    = each.key
  name                         = "AI gateway platform client ${each.key}"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = true
  access_token_lifespan        = "300"
  full_scope_allowed           = false
}

resource "keycloak_openid_client_default_scopes" "ai_platform" {
  for_each  = keycloak_openid_client.ai_platform
  realm_id  = keycloak_realm.kube_lab.id
  client_id = each.value.id
  default_scopes = [
    "basic",
    keycloak_openid_client_scope.ai_gateway.name,
  ]
}

resource "keycloak_user_groups" "ai_platform" {
  for_each   = keycloak_openid_client.ai_platform
  realm_id   = keycloak_realm.kube_lab.id
  user_id    = each.value.service_account_user_id
  group_ids  = [keycloak_group.ai_platform.id]
  exhaustive = false
}

# -----------------------------------------------------------------------------
# Client Policy: every client that holds the ai-gateway scope by default is
# confidential, has no full scope and cannot use implicit or password grants.
# -----------------------------------------------------------------------------
resource "keycloak_realm_client_policy_profile" "ai_clients" {
  realm_id    = keycloak_realm.kube_lab.id
  name        = "cnp-ai-clients"
  description = "Clients of the AI gateway"

  executor {
    name = "confidential-client"
  }

  executor {
    name = "full-scope-disabled"
    configuration = {
      "auto-configure" = "true"
    }
  }

  executor {
    name = "reject-implicit-grant"
    configuration = {
      "auto-configure" = "true"
    }
  }

  executor {
    name = "reject-ropc-grant"
    configuration = {
      "auto-configure" = "true"
    }
  }
}

resource "keycloak_realm_client_policy_profile_policy" "ai_clients" {
  realm_id    = keycloak_realm.kube_lab.id
  name        = "cnp-ai-clients"
  description = "Clients with the ai-gateway default scope"
  enabled     = true
  profiles    = [keycloak_realm_client_policy_profile.ai_clients.name]

  condition {
    name = "client-scopes"
    configuration = {
      type   = "Default"
      scopes = jsonencode([keycloak_openid_client_scope.ai_gateway.name])
    }
  }
}

# -----------------------------------------------------------------------------
# Vault
# -----------------------------------------------------------------------------
# kvv2/platform/ai/anthropic (key api-key) is written by hand, never by
# Terraform; only the ai-gateway namespace syncs it (Kyverno ai-no-provider-keys).
resource "vault_kv_secret_v2" "ai_platform_clients" {
  for_each = {
    "sandbox-runner"   = keycloak_openid_client.sandbox_runner
    "ai-gateway-smoke" = keycloak_openid_client.ai_platform["ai-gateway-smoke"]
  }
  mount = vault_mount.kvv2.path
  name  = "platform/ai-clients/${each.key}"
  data_json = jsonencode({
    "client_id"     = each.value.client_id
    "client_secret" = each.value.client_secret
  })
}

resource "vault_kv_secret_v2" "arcl_cmp_ai_client" {
  mount = vault_mount.kvv2.path
  name  = "arcl-cmp/ai-gateway-client"
  data_json = jsonencode({
    "client_id"     = keycloak_openid_client.ai_platform["cmp-ai"].client_id
    "client_secret" = keycloak_openid_client.ai_platform["cmp-ai"].client_secret
  })
}

resource "vault_policy" "ai_gateway_policy" {
  name = "ai-gateway-policy"
  policy = templatefile("${path.module}/policies/ai_gateway.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

resource "vault_kubernetes_auth_backend_role" "ai_gateway_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "ai-gateway-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.ai_gateway_policy.name]
}

resource "vault_policy" "ai_clients_policy" {
  name = "ai-clients-policy"
  policy = templatefile("${path.module}/policies/ai_clients.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

resource "vault_kubernetes_auth_backend_role" "ai_clients_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "ai-clients-role"
  bound_service_account_names      = ["vault-secrets-operator"]
  bound_service_account_namespaces = ["vault-secrets-operator"]
  token_ttl                        = 86400
  token_policies                   = [vault_policy.ai_clients_policy.name]
}
