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
  policy = templatefile("${path.module}/policies/keycloak.hcl", {
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
