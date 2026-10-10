# Vault refuses every request when no audit device can write, so stdout: Alloy
# ships it to Loki (30d, see the vault namespace label), and there is no file
# on a 2Gi PVC to fill up.
resource "vault_audit" "stdout" {
  type = "file"
  path = "stdout"

  options = {
    file_path = "stdout"
  }
}

resource "keycloak_realm_events" "kube_lab" {
  realm_id = keycloak_realm.kube_lab.id

  events_enabled    = true
  events_expiration = 2592000 # 30 days, matching the Loki retention

  admin_events_enabled         = true
  admin_events_details_enabled = false

  events_listeners = ["jboss-logging"]
}
