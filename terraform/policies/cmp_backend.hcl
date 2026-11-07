# CMP backend (role cmp-backend): provisions projects through the
# app-templates modules and reads/writes project secrets. Everything it may
# create or change is named project-* except app auth roles, which carry no
# prefix: the platform roles are denied by name below.
#
# Limits, on purpose spelled out:
# - The CMP writes the content of project-* policies, so it can grant itself
#   anything through one of them: this policy keeps it off the platform
#   objects, it does not bound what a compromised CMP can reach.
# - The kubernetes auth plugin lowercases role names and policy paths are
#   case-sensitive: the name denies stop exact names only. A mixed-case write
#   can still overwrite a platform role, but only with the bindings the
#   allowed_parameters below permit (vault-secrets-operator, project-*
#   policies); a mixed-case delete is not stopped.
# - "*,*" (contains a comma) blocks comma-separated lists, which Vault splits
#   after the parameter check.

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/mounts/project-*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "project-*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}

path "${kv_mount}/data/projects/*" {
  capabilities = ["read"]
}

path "sys/policies/acl/project-*" {
  capabilities = ["create", "read", "update", "delete"]
}

# data "vault_auth_backend" "oidc", for the accessor of the group aliases.
path "sys/mounts/auth/oidc" {
  capabilities = ["read"]
}

%{ for mount in auth_mounts ~}
path "auth/${mount}/role/*" {
  capabilities = ["create", "read", "update", "delete"]
  allowed_parameters = {
    "token_policies"                   = ["project-*"]
    "policies"                         = ["project-*"]
    "bound_service_account_names"      = ["vault-secrets-operator"]
    "bound_service_account_namespaces" = ["vault-secrets-operator"]
    # Sent by the provider on every write, empty; a selector would widen the
    # namespace binding.
    "bound_service_account_namespace_selector" = [""]
    "*"                                        = []
  }
  denied_parameters = {
    "token_policies"                   = ["*,*"]
    "policies"                         = ["*,*"]
    "bound_service_account_names"      = ["*,*"]
    "bound_service_account_namespaces" = ["*,*"]
  }
}

%{ endfor ~}
%{ for mount, roles in denied_roles ~}
%{ for role in roles ~}
path "auth/${mount}/role/${role}" {
  capabilities = ["deny"]
}

%{ endfor ~}
%{ endfor ~}
# Project groups: created by name, then managed by id. The platform groups
# are out of reach, and no alias may point at them.
path "identity/group" {
  capabilities = ["create", "update"]
  allowed_parameters = {
    "name"     = ["project-*"]
    "policies" = ["project-*"]
    "type"     = ["external"]
    "*"        = []
  }
  denied_parameters = {
    "id"                = []
    "member_entity_ids" = []
    "member_group_ids"  = []
    "policies"          = ["*,*"]
  }
}

path "identity/group/id/*" {
  capabilities = ["read", "update", "delete"]
  allowed_parameters = {
    "name"     = ["project-*"]
    "policies" = ["project-*"]
    "type"     = ["external"]
    "*"        = []
  }
  denied_parameters = {
    "member_entity_ids" = []
    "member_group_ids"  = []
    "policies"          = ["*,*"]
  }
}

path "identity/group-alias" {
  capabilities = ["create", "update"]
  denied_parameters = {
    "id"           = []
    "canonical_id" = ${jsonencode(platform_group_ids)}
  }
}

path "identity/group-alias/id/*" {
  capabilities = ["read", "update", "delete"]
  denied_parameters = {
    "canonical_id" = ${jsonencode(platform_group_ids)}
  }
}

%{ for id in platform_group_ids ~}
path "identity/group/id/${id}" {
  capabilities = ["deny"]
}

%{ endfor ~}
%{ for id in platform_group_alias_ids ~}
path "identity/group-alias/id/${id}" {
  capabilities = ["deny"]
}

%{ endfor ~}
%{ for name in platform_group_names ~}
path "identity/group/name/${name}" {
  capabilities = ["deny"]
}

%{ endfor ~}
