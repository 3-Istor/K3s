# kube-system (Cilium)

## WireGuard encryption maintenance (CNP-298)

`encryption.type: wireguard` makes each Cilium agent create a `cilium_wg0`
interface and encrypt pod-to-pod traffic that leaves the node. Node-to-node
host traffic stays as it is (`nodeEncryption` is off). The pod MTU drops by
about 80 bytes; Cilium sets it itself.

Changing the agent ConfigMap does not restart the agents: Argo CD syncs the
values, the restart below applies them. Until both agents run with WireGuard,
pods on the two nodes cannot talk to each other, so do it in an announced
window. Agents restart one at a time (`maxUnavailable: 1`).

SSH as in `node-config/k3s-server/README.md`; the worker is reached the same
way. `cilium` is the CLI inside the agent pod:
`kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg ...`.

### Before the window

1. The WireGuard module is in both kernels (built in since Linux 5.6):

   ```bash
   sudo modprobe wireguard && lsmod | grep -w wireguard
   ```

   A failure here stops the procedure on that node.

2. Record the baseline for the ticket: agent CPU
   (`kubectl -n kube-system top pod -l k8s-app=cilium`) and the pod MTU
   (`kubectl exec <any pod> -- cat /sys/class/net/eth0/mtu`).

3. Capture the cleartext baseline on the worker, while hitting a pod on the
   other node over HTTP:

   ```bash
   sudo tcpdump -ni ens3 -A -c 20 'udp port 8472' | grep -i 'HTTP/1.1'
   ```

   VXLAN on 8472 carries the HTTP payload readable. Use the node's real
   interface name in place of `ens3`.

4. List the apps that set their own MTU (`grep -ri mtu` on their values);
   they must stay at or below the new pod MTU.

### In the window

1. Merge the PR and let Argo CD sync `kube-system`. Agents keep running the
   old config.
2. Restart the worker's agent first:

   ```bash
   kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=k3s-worker-node
   kubectl -n kube-system rollout status ds/cilium
   ```

3. Then the server's agent (`spec.nodeName=my-k3s-cluster-node`), same commands.
4. Restart the operator: `kubectl -n kube-system rollout restart deploy/cilium-operator`.

### Checks

- `cilium-dbg encrypt status` on each agent: `Encryption: Wireguard`, one peer.
- `ip -d link show cilium_wg0` exists on both nodes.
- Capture again: `sudo tcpdump -ni ens3 -c 20 'udp port 51871'` shows the
  traffic, and the step 3 command finds no `HTTP/1.1` in clear.
- Pod MTU and agent CPU after, noted in the ticket.
- Every app answers (Gatus, `kubectl get pods -A | grep -v Running`).

### Rollback

Revert the PR (or set `encryption.enabled: false`), let Argo CD sync, then
restart the agents in the same order. Pods recover cross-node traffic once
both agents run without WireGuard.
