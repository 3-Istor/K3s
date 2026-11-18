# Storage migration to Ceph pool `kubernetes` (CNP-315, CNP-189)

Moves every PV off `local-path` and off `ceph-block` (Cinder's pool `volumes`)
onto `ceph-rbd` (pool `kubernetes`), then restricts the CSI cephx users to that
pool. Garage is removed in the same window; its buckets were copied to the RGW
beforehand (`garage-to-rgw.yaml`).

Old volumes are never modified: the copy mounts them read-only and their PV is
switched to `Retain`. Rolling back one claim means recreating it on its old PV.

## Before the window

- Pool `kubernetes` exists (16 PGs, size 3, application rbd).
- `ceph-rbd` StorageClass applied, `migrate-pvc.sh` tested on a throwaway claim.
- Garage buckets copied and checked: `user-avatars` (3), `cnp-app-icons` (1),
  `cnp-project-exports` (0), `loki-data` to `loki-garage-archive`.
- Vault unseal keys at hand: Vault restarts sealed.

## Window

All commands use `kubectl --context 3-istor-prod@kubernetes` (`k` below).

1. Stop Argo from reverting anything:
   `k -n argocd scale statefulset argocd-application-controller --replicas=0`
2. Keycloak central dump, the one database nothing else can rebuild:
   `k -n keycloak exec deploy/keycloak-db -- pg_dumpall -U postgres > keycloak-$(date +%F).sql`
3. Shared Keycloak database down to one instance, the primary:
   `k -n cnp-projects-db patch cluster cnp-projects-keycloak --type=merge -p '{"spec":{"instances":1}}'`
   and wait until only the primary pod is left. Its old replicas' PVCs go with them.
4. Stop the workloads (record replicas first: `k get deploy,sts -A -o wide > replicas.txt`):
   - Deployments to 0: `keycloak/keycloak-db`, `keycloak` keycloakx StatefulSet,
     `3istor-sessions/sessions-postgres`, `arcl-cmp/arcl-cmp-backend`,
     `mepa-app/mepa`, `observability/grafana`, `observability/vmsingle-cnp`,
     `observability/vlsingle-cnp`.
   - StatefulSets to 0: `vault/vault`, `observability/loki`,
     `observability/alertmanager`, `observability/vtraces-cnp`, the four
     `epitweet-*` backing ones. Operators (VM operator, Prometheus-style
     alertmanager) are scaled to 0 first so they do not scale them back.
   - CNPG clusters: `k annotate cluster <name> cnpg.io/hibernation=on` in
     `cnp-projects-db`, `iot-optispace`, `iot-optispace-stg`, `test-hugo-optispace`.
5. Move every claim, one by one (`scripts/migrate-pvc.sh <ns> <pvc>`):

   | Namespace | PVC | From |
   |---|---|---|
   | vault | data-vault-0, audit-vault-0 | local-path |
   | keycloak | postgres-pvc | local-path |
   | cnp-projects-db | the remaining cnp-projects-keycloak-N | local-path |
   | iot-optispace | iot-optispace-backend-db-1 | local-path |
   | iot-optispace-stg | iot-optispace-backend-stg-db-1 | local-path |
   | test-hugo-optispace | test-hugo-optispace-backend-db-1 | local-path |
   | 3istor-sessions | sessions-postgres-pvc | local-path |
   | qcm | qcm-postgres-pvc | local-path |
   | arcl-cmp | arcl-cmp-backend-data, arcl-cmp-backend-db | local-path |
   | mepa-app | mepa | local-path |
   | observability | grafana, vmsingle-cnp, vlsingle-cnp, storage-vtraces-cnp-0, storage-alertmanager-0, storage-loki-0, vmstorage-volume-vm-victoria-metrics-cluster-vmstorage-0 | ceph-block |
   | epitweet-* | data-mongodb-0, data-redis-0, data-neo4j-0, data-elasticsearch-0 | ceph-block |

   `default/arcl-cmp-backend-data` and `default/arcl-cmp-backend-db` are
   leftovers of an April Helm install, mounted by nothing: back them up with a
   copy, then delete them.
6. Garage: set its two PVs to `Retain`, then merge the K3s PR (which removes
   the Argo app) and the infra-templates PR.
7. local-path no longer default: see `node-config/k3s-server/README.md`.
8. Restart: scale the Argo controller back to 1 and sync; remove the CNPG
   hibernation annotations; scale the workloads back from `replicas.txt`.
   Unseal Vault.
9. Check: Keycloak login, Vault unsealed and VaultSecrets synced, CMP pages
   with avatars and app icons, a project export, Grafana dashboards with
   history, project apps up, `k get pvc -A | grep -v ceph-rbd` empty.

## After the window

- Restrict the CSI users to the new pool, once nothing lives in `volumes`:

  ```bash
  sudo cephadm shell -- ceph auth caps client.csi-rbd-node \
    mon 'profile rbd, allow command "osd blocklist"' osd 'profile rbd pool=kubernetes'
  sudo cephadm shell -- ceph auth caps client.csi-rbd-provisioner \
    mon 'profile rbd, allow command "osd blocklist"' mgr 'profile rbd pool=kubernetes' \
    osd 'profile rbd pool=kubernetes'
  ```

- After a week without issue: delete the retained old PVs (`k get pv | grep
  Released`), the `ceph-block` StorageClass, the temporary Garage key and
  `garage-migration-ro` Secrets.
