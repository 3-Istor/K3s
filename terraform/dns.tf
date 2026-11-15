################### A and AAAA Records ##################################

resource "cloudflare_dns_record" "a_root_record" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "A"
  content = var.dc_ip
  ttl     = 1 # Auto
  proxied = false
}

# WireGuard endpoint for the team's laptops. Clients use this name instead of the box IP,
# so an IP change is one dc_ip update. Not proxied: Cloudflare does not relay UDP.
resource "cloudflare_dns_record" "vpn" {
  zone_id = var.cloudflare_zone_id
  name    = "vpn"
  type    = "A"
  content = var.dc_ip
  ttl     = 300
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
