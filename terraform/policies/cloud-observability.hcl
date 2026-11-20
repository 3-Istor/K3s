# Until the end of CNP-185 V2: the cloud's Alloy still ships logs to Loki.
path "kvv2/data/observability/loki-clients" {
  capabilities = ["read"]
}

# Only this cloud's vmauth credentials: a cloud cannot write as another.
path "kvv2/data/observability/clouds/${cloud}" {
  capabilities = ["read"]
}
