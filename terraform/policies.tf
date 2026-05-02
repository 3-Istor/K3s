# resource "vault_policy" "fixme_policy" {
#   name = "fixme-policy"
#   policy = templatefile("${path.module}/policies/fixme.hcl", {
#     mount_path = vault_mount.kvv2.path
#   })
# }

# -----------------------------------------------------------------------------
# Cert-Manager Policies
# -----------------------------------------------------------------------------

resource "vault_policy" "cert_manager_policy" {
  name = "cert-manager-policy"
  policy = templatefile("${path.module}/policies/cert_manager.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# Keycloak Policies
# -----------------------------------------------------------------------------

resource "vault_policy" "keycloak_policy" {
  name = "keycloak-policy"
  policy = templatefile("${path.module}/policies/keycloak.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# Cloudflared Policies
# -----------------------------------------------------------------------------

resource "vault_policy" "cloudflared_policy" {
  name = "cloudflared-policy"
  policy = templatefile("${path.module}/policies/cloudflared.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# Demo App Policies
# -----------------------------------------------------------------------------

resource "vault_policy" "demo_app_policy" {
  name = "demo-app-policy"
  policy = templatefile("${path.module}/policies/demo_app.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# Operator Policies
# -----------------------------------------------------------------------------

resource "vault_policy" "vault_secrets_operator_policy" {
  name = "vault-secrets-operator-policy"
  policy = templatefile("${path.module}/policies/vault_secrets_operator.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# ArgoCD Policies
# -----------------------------------------------------------------------------
resource "vault_policy" "argocd_policy" {
  name = "argocd-policy"
  policy = templatefile("${path.module}/policies/argocd.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# Vault Admin Policies
# -----------------------------------------------------------------------------
resource "vault_policy" "vault_admin" {
  name = "vault-admin"
  policy = templatefile("${path.module}/policies/vault_admin.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}

# -----------------------------------------------------------------------------
# CMP Policies
# -----------------------------------------------------------------------------
resource "vault_policy" "arcl_cmp_policy" {
  name   = "arcl-cmp-policy"
  policy = templatefile("${path.module}/policies/arcl_cmp.hcl", {})
}

# -----------------------------------------------------------------------------
# n8n Policies
# -----------------------------------------------------------------------------
resource "vault_policy" "n8n_policy" {
  name = "n8n-policy"
  policy = templatefile("${path.module}/policies/n8n.hcl", {
    mount_path = vault_mount.kvv2.path
  })
}
