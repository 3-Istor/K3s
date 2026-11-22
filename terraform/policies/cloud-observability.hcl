# Only this cloud's vmauth credentials: a cloud cannot write as another.
path "kvv2/data/observability/clouds/${cloud}" {
  capabilities = ["read"]
}
