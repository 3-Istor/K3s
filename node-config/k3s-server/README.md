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
touched. The audit log is read by Fluent Bit from
`/var/lib/rancher/k3s/server/logs/audit.log` and shipped to VictoriaLogs.

Daily trim: install `fstrim.timer.d/daily.conf` to `/etc/systemd/system/fstrim.timer.d/`, then `sudo systemctl daemon-reload && sudo systemctl restart fstrim.timer`.

## Datastore

The server runs embedded etcd (`cluster-init: true`) since 2026-11-21. It was
converted in place from kine/SQLite: K3s migrates `db/state.db` into
`db/etcd/` on the first start with `cluster-init`, and renames the old file
to `state.db.migrated`. Never remove `cluster-init` again: K3s would start on
the old SQLite file and lose everything written since.

etcd fsyncs every write, and the node disk is an RBD image on Ceph: watch
`etcd_disk_wal_fsync_duration_seconds` on `127.0.0.1:2381/metrics` (about
40 ms on average at migration time).

Restore a snapshot:

```bash
sudo systemctl stop k3s
sudo k3s server --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<name>
sudo systemctl start k3s
```

## local-path is not the default StorageClass

Persistent volumes live on Ceph (`ceph-rbd`, pool `kubernetes`, CNP-315).
K3s re-writes its local-storage manifest at every start, which marks
`local-path` as default again. The `.skip` file stops that; the provisioner
keeps running for whatever still needs a node-local volume.

```bash
ssh -i ~/.ssh/kp_admin_openstack -J pae-node-1 ubuntu@192.168.1.212 \
  'sudo touch /var/lib/rancher/k3s/server/manifests/local-storage.yaml.skip'
kubectl --context 3-istor-prod@kubernetes annotate sc local-path \
  storageclass.kubernetes.io/is-default-class=false --overwrite
```
