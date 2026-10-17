#!/bin/sh
# On-prem WireGuard peer: initiates the tunnel towards one cloud pod (EKS or GKE)
# and relays only the declared TCP flows (same model as wireguard/gateway.py on the cloud side).
set -eu

PIDS=""

cleanup() {
  for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
  ip link delete wg0 2>/dev/null || true
}
trap 'cleanup; exit 0' TERM INT

# The pod network namespace survives container restarts: drop a leftover wg0
ip link delete wg0 2>/dev/null || true
ip link add wg0 type wireguard
ip address add "$ONPREM_TUNNEL_ADDRESS" dev wg0
wg set wg0 private-key /secrets/privatekey
ip link set wg0 mtu "$MTU" up

# Endpoint published by Terraform on every cloud up (Cloud repo, module cluster-addons).
fetch_endpoint() {
  python3 -c 'import sys, urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=10).read().decode().strip())' \
    "$CLOUD_ENDPOINT_URL" 2>/dev/null || true
}

set_peer() {
  ep=$(fetch_endpoint)
  if [ -z "$ep" ]; then
    echo "no endpoint at $CLOUD_ENDPOINT_URL yet: wg0 up without peer"
    return 0
  fi
  # On-prem is behind NAT: it initiates and keeps the mapping open
  wg set wg0 peer "$CLOUD_PUBLIC_KEY" endpoint "$ep" \
    allowed-ips "$CLOUD_TUNNEL_IP/32" persistent-keepalive 25
  echo "peer endpoint $ep"
}

set_peer
echo "on-prem public key: $(wg show wg0 public-key)"

# onprem-to-cloud: on-prem pods -> Service aws-apps / gcp-apps -> cloud relay port
socat "TCP4-LISTEN:$ONPREM_TO_CLOUD_PORT,bind=$POD_IP,reuseaddr,fork" \
  "TCP4:$CLOUD_TUNNEL_IP:$ONPREM_TO_CLOUD_PORT" &
PIDS="$PIDS $!"

# cloud-to-onprem: only reachable through the tunnel IP
socat "TCP4-LISTEN:$CLOUD_TO_ONPREM_PORT,bind=${ONPREM_TUNNEL_ADDRESS%/*},reuseaddr,fork" \
  "TCP4:$CLOUD_TO_ONPREM_TARGET" &
PIDS="$PIDS $!"

# Exit (and let Kubernetes restart the container) if a relay dies
i=0
while true; do
  for pid in $PIDS; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "relay $pid stopped" >&2
      cleanup
      exit 1
    fi
  done
  # The cloud worker's IP changes on every up: re-read the endpoint once the tunnel goes quiet.
  i=$((i + 1))
  if [ $((i % 12)) -eq 0 ]; then
    last=$(wg show wg0 latest-handshakes | awk '{print $2}')
    if [ $(( $(date +%s) - ${last:-0} )) -gt 180 ]; then set_peer; fi
  fi
  sleep 5 &
  wait $!
done
