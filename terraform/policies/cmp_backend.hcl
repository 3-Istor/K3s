# CMP backend (role cmp-backend): provisions projects through the
# app-templates modules and reads/writes project secrets. Everything it may
# create or change is named project-* except app auth roles, which carry no
# prefix: the platform roles are denied by name below.
#
# The policy-name globs on roles and groups only stop naming a platform policy
# directly: a comma-separated string passes the glob, and the CMP writes the
# content of project-* policies anyway. They are a guard rail, not a bound.

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
    "token_policies" = ["project-*"]
    "policies"       = ["project-*"]
    "*"              = []
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
    "*"        = []
  }
}

path "identity/group/id/*" {
  capabilities = ["read", "update", "delete"]
  allowed_parameters = {
    "name"     = ["project-*"]
    "policies" = ["project-*"]
    "*"        = []
  }
}

path "identity/group-alias" {
  capabilities = ["create", "update"]
  denied_parameters = {
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
