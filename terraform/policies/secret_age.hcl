# Metadata only: version timestamps, never the secret values under data/.
path "${mount_path}/metadata/*" {
  capabilities = ["list", "read"]
}
