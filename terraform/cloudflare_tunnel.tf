locals {
  tunnel_services = toset([
    "auth",
    "admin-auth",
    "argocd",
    "vault",
    "demo"
  ])

  tunnel_secret_b64 = base64encode(random_password.tunnel_secret.result)

  generated_tunnel_token = base64encode(jsonencode({
    a = var.cloudflare_account_id
    t = cloudflare_zero_trust_tunnel_cloudflared.k3s_tunnel.id
    s = local.tunnel_secret_b64
  }))
}

resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "k3s_tunnel" {
  account_id    = var.cloudflare_account_id
  name          = "3istor-cloud-tunnel"
  config_src    = "cloudflare"
  tunnel_secret = local.tunnel_secret_b64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k3s_tunnel_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s_tunnel.id

  config = {
    ingress = concat(
      [
        for svc in local.tunnel_services : {
          hostname = "${svc}.${var.domain_name}"
          service  = "http://envoy-gateway-infra-shared-gateway-ac1e5388.envoy-gateway-system.svc.cluster.local:80"
        }
      ],
      [
        {
          service = "http_status:404"
        }
      ]
    )
  }
}
