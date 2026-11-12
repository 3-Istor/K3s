# Every project's secrets (the project-<name> KV mounts), read and write.
# Held only through the elevated-vault-data Keycloak group, which the CMP
# fills for the length of an approved just-in-time grant (CNP-124).
path "project-*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
