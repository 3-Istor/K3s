# K3s agent configuration

`k3s-worker-node` (192.168.1.213) reads `/etc/rancher/k3s/config.yaml` on top of
the flags in its systemd unit.

Apply:

```bash
scp -i ~/.ssh/kp_admin_openstack -o ProxyJump=pae-node-1 \
  config.yaml ubuntu@192.168.1.213:/tmp/
ssh -i ~/.ssh/kp_admin_openstack -J pae-node-1 ubuntu@192.168.1.213 \
  'sudo install -D -m 0600 /tmp/config.yaml /etc/rancher/k3s/config.yaml \
   && sudo systemctl restart k3s-agent'
```

Restarting the agent keeps running containers; the node is NotReady for a few
seconds.
