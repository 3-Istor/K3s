# Vault Admin Policy
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Project secrets are not standing access (CNP-124): reading or writing them
# takes the vault-data elevation, whose policy adds the other capabilities on
# this same path. Listing stays, to see what exists. Not a deny: a deny here
# would also cancel the elevation, which the same people hold.
#
# This is a guardrail, not a wall: this policy still writes sys/policies and
# identity, so an admin can grant themselves the rest. The audit device and
# the Loki rules are what catch that.
path "project-*" {
  capabilities = ["list"]
}
