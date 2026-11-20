# Dead man's switch of the alerting chain (CNP-185 V3). The Watchdog alert
# always fires and Alertmanager pings this check every 5 minutes. When the
# pings stop (VMAlert, Alertmanager or the cluster down), healthchecks.io
# alerts through its Discord integration, which lives outside the cluster.
variable "healthchecksio_api_key" {
  description = "Read-write API key of the healthchecks.io project (Settings > API Access)"
  type        = string
  sensitive   = true
}

# The Discord integration is created once in the healthchecks.io UI: its
# webhook cannot be set through the API.
data "healthchecksio_channel" "discord" {
  kind = "discord"
}

resource "healthchecksio_check" "alerting_watchdog" {
  name     = "cnp-alerting-watchdog"
  desc     = "Watchdog alert of the CNP on-prem cluster, sent by VMAlertmanager every 5 minutes."
  tags     = ["cnp", "onprem", "alerting"]
  timeout  = 300
  grace    = 600
  channels = [data.healthchecksio_channel.discord.id]
}

# Whoever holds the ping URL can keep the check green: Vault only, never git.
resource "vault_kv_secret_v2" "alerting_healthchecks" {
  mount = vault_mount.kvv2.path
  name  = "observability/healthchecks"
  data_json = jsonencode({
    "PING_URL" = healthchecksio_check.alerting_watchdog.ping_url
  })
}
