# K3s server configuration

The K3s server (`my-k3s-cluster-node`, 192.168.1.212) was installed by hand;
these are its configuration files, kept here so they can be reviewed and
reinstalled.

Reach it through pae-node-1:

```bash
ssh -i ~/.ssh/kp_admin_openstack -J pae-node-1 ubuntu@192.168.1.212
```

Apply:

```bash
scp -i ~/.ssh/kp_admin_openstack -o ProxyJump=pae-node-1 \
  config.yaml audit-policy.yaml ubuntu@192.168.1.212:/tmp/
ssh -i ~/.ssh/kp_admin_openstack -J pae-node-1 ubuntu@192.168.1.212 \
  'sudo install -m 0600 /tmp/config.yaml /tmp/audit-policy.yaml /etc/rancher/k3s/ \
   && sudo systemctl restart k3s'
```

The restart stops the API server for about a minute; running pods are not
touched. The audit log is read by Alloy from
`/var/lib/rancher/k3s/server/logs/audit.log` and kept 30 days in Loki.
