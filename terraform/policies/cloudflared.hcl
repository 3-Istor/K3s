# Cloudflared Policy
path "${mount_path}/data/cloudflared/*" {
  capabilities = ["read"]
}
