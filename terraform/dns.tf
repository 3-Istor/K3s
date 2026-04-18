################### A and AAAA Records ##################################

resource "cloudflare_dns_record" "3istor_a_root_record" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "A"
  content = var.dc_ip
  ttl     = 1 # Auto
  proxied = false
}

#########################################################################

######################## CNAME 3Istor Cluster ########################

locals {
  cluster_cnames = {
    # Proxied (Orange Cloud)
    "argocd" = true
    # "grafana"     = true
    "vault" = true
    # "www"         = true

    # DNS Only (Grey Cloud)
    "auth" = false
  }
}

resource "cloudflare_dns_record" "cluster_services" {
  for_each = local.cluster_cnames

  zone_id = var.cloudflare_zone_id
  name    = each.key
  type    = "CNAME"
  content = var.domain_name
  ttl     = 1 # Auto
  proxied = each.value
}

#########################################################################
