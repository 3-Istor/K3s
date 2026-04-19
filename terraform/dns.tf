################### A and AAAA Records ##################################

resource "cloudflare_dns_record" "a_root_record" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "A"
  content = var.dc_ip
  ttl     = 1 # Auto
  proxied = false
}

#########################################################################

######################## CNAME 3Istor Cluster ########################

resource "cloudflare_dns_record" "cluster_services" {
  for_each = local.tunnel_services

  zone_id = var.cloudflare_zone_id
  name    = each.key
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s_tunnel.id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

#########################################################################
