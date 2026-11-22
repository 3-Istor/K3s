# gVisor on the K3s nodes

`RuntimeClass/gvisor` (handler `runsc`, in `k8s/config/sandbox-runtimes/`) runs the
AI sandboxes and agents that ask for `cnp.3istor.com/isolation: gvisor`. Both
nodes need `runsc`, its containerd shim and a containerd drop-in. Version and
checksum are pinned in `install.sh`.

Apply on one node, restart K3s on that node, check, then do the other node.
Never both at once: the restart restarts containerd, running pods survive but
the node is NotReady for a few seconds.

```bash
node=192.168.1.213   # k3s-worker-node first, then 192.168.1.212 (server)
unit=k3s-agent       # k3s on the server
scp -i ~/.ssh/kp_admin_openstack -o ProxyJump=pae-node-1 \
  install.sh gvisor.toml runsc.toml ubuntu@$node:/tmp/
ssh -i ~/.ssh/kp_admin_openstack -J pae-node-1 ubuntu@$node \
  "sudo mkdir -p /opt/cnp/gvisor && sudo install -m 0644 /tmp/gvisor.toml /tmp/runsc.toml /opt/cnp/gvisor/ \
   && sudo install -m 0755 /tmp/install.sh /opt/cnp/gvisor/ && sudo /opt/cnp/gvisor/install.sh \
   && sudo systemctl restart $unit"
```

Check on the node, then from the cluster:

```bash
sudo k3s crictl info | jq '.config.containerd.runtimes | keys'   # has "runsc"
kubectl get nodes; kubectl get pods -A | grep -vE 'Running|Completed'
```
