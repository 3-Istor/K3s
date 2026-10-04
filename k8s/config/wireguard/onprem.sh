#!/bin/sh
# On-prem WireGuard peer: initiates the tunnel towards the AWS pod and relays
# only the declared TCP flows (same model as wireguard/gateway.py on EKS).
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

if [ -n "$AWS_PUBLIC_KEY" ] && [ -n "$AWS_ENDPOINT" ]; then
  # On-prem is behind NAT: it initiates and keeps the mapping open
  wg set wg0 peer "$AWS_PUBLIC_KEY" \
    endpoint "$AWS_ENDPOINT" \
    allowed-ips "$AWS_TUNNEL_IP/32" \
    persistent-keepalive 25
  echo "wg0 up, peer $AWS_ENDPOINT"
else
  echo "AWS_ENDPOINT/AWS_PUBLIC_KEY empty: wg0 up without peer"
fi
echo "on-prem public key: $(wg show wg0 public-key)"

# onprem-to-aws: on-prem pods -> Service aws-apps -> AWS relay port
socat "TCP4-LISTEN:$ONPREM_TO_AWS_PORT,bind=$POD_IP,reuseaddr,fork" \
  "TCP4:$AWS_TUNNEL_IP:$ONPREM_TO_AWS_PORT" &
PIDS="$PIDS $!"

# aws-to-onprem: only reachable through the tunnel IP
socat "TCP4-LISTEN:$AWS_TO_ONPREM_PORT,bind=${ONPREM_TUNNEL_ADDRESS%/*},reuseaddr,fork" \
  "TCP4:$AWS_TO_ONPREM_TARGET" &
PIDS="$PIDS $!"

# Exit (and let Kubernetes restart the container) if a relay dies
while true; do
  for pid in $PIDS; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "relay $pid stopped" >&2
      cleanup
      exit 1
    fi
  done
  sleep 5 &
  wait $!
done
