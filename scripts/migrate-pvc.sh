#!/usr/bin/env bash
# Move one PVC to another StorageClass, keeping its name, labels, annotations
# and owner references, so the workload and Argo CD see the same claim.
#
# The workload must already be stopped: nothing may mount the PVC.
# The old PV is switched to Retain and left in place (Released) for rollback.
#
# Usage: migrate-pvc.sh <namespace> <pvc> [storage-class]
set -euo pipefail

NAMESPACE=$1
PVC=$2
TARGET_CLASS=${3:-ceph-rbd}
KUBECTL=${KUBECTL:-kubectl --context 3-istor-prod@kubernetes}
COPY_IMAGE=${COPY_IMAGE:-docker.io/library/alpine:3.22.2}
TMP_PVC="${PVC:0:50}-mig"
JOB="mig-${PVC:0:50}"
k() { $KUBECTL -n "$NAMESPACE" "$@"; }
log() { printf '[%s] %s/%s: %s\n' "$(date -u +%H:%M:%S)" "$NAMESPACE" "$PVC" "$*"; }

OLD_JSON=$(k get pvc "$PVC" -o json)
OLD_PV=$(jq -r .spec.volumeName <<<"$OLD_JSON")
OLD_CLASS=$(jq -r .spec.storageClassName <<<"$OLD_JSON")
SIZE=$(jq -r .spec.resources.requests.storage <<<"$OLD_JSON")

if [[ $OLD_CLASS == "$TARGET_CLASS" ]]; then
  log "already on $TARGET_CLASS, nothing to do"
  exit 0
fi

USERS=$(k get pods -o json | jq -r --arg c "$PVC" \
  '.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed")
   | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $c)) | .metadata.name')
if [[ -n $USERS ]]; then
  echo "refusing: $PVC is still mounted by: $USERS" >&2
  exit 1
fi

log "old PV $OLD_PV ($OLD_CLASS, $SIZE) -> Retain"
$KUBECTL patch pv "$OLD_PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' >/dev/null

if ! k get pvc "$TMP_PVC" >/dev/null 2>&1; then
  k apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TMP_PVC
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: $TARGET_CLASS
  resources:
    requests:
      storage: $SIZE
EOF
fi

# Same pod mounts both claims: the local-path PV pins it to the old node and
# RBD attaches anywhere. The second rsync pass is a checksum dry-run and must
# report nothing, otherwise the job fails and the swap never happens.
log "copying"
k delete job "$JOB" --ignore-not-found >/dev/null
k apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: copy
          image: $COPY_IMAGE
          command: ["/bin/sh", "-ec"]
          args:
            - |
              apk add --no-cache rsync >/dev/null
              rsync -aHAX --numeric-ids /src/ /dst/
              diff=\$(rsync -aHAXc --numeric-ids --dry-run --itemize-changes --exclude=/lost+found /src/ /dst/)
              if [ -n "\$diff" ]; then echo "VERIFY FAILED"; echo "\$diff" | head -50; exit 1; fi
              echo "files src=\$(find /src | wc -l) dst=\$(find /dst -path /dst/lost+found -prune -o -print | wc -l)"
              du -s /src /dst
              echo VERIFIED
          resources:
            requests: {cpu: 100m, memory: 256Mi}
            limits: {memory: 256Mi}
          volumeMounts:
            - {name: src, mountPath: /src, readOnly: true}
            - {name: dst, mountPath: /dst}
      volumes:
        - name: src
          persistentVolumeClaim: {claimName: $PVC, readOnly: true}
        - name: dst
          persistentVolumeClaim: {claimName: $TMP_PVC}
EOF
if ! k wait --for=condition=complete "job/$JOB" --timeout=30m; then
  k logs "job/$JOB" --tail=60 >&2 || true
  echo "copy failed: old PVC untouched, temporary PVC $TMP_PVC left for inspection" >&2
  exit 1
fi
k logs "job/$JOB" --tail=5
k logs "job/$JOB" --tail=1 | grep -qx VERIFIED

NEW_PV=$(k get pvc "$TMP_PVC" -o jsonpath='{.spec.volumeName}')
log "swapping onto $NEW_PV"
$KUBECTL patch pv "$NEW_PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' >/dev/null
k delete job "$JOB" --wait=true >/dev/null
k delete pvc "$TMP_PVC" --wait=true >/dev/null
$KUBECTL patch pv "$NEW_PV" --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]' >/dev/null
k delete pvc "$PVC" --wait=true >/dev/null

jq --arg pv "$NEW_PV" --arg class "$TARGET_CLASS" '
  {apiVersion, kind,
   metadata: (.metadata | {name, namespace, labels, ownerReferences,
     annotations: ((.annotations // {}) | with_entries(select(.key
       | test("^(pv\\.kubernetes\\.io|volume\\.kubernetes\\.io|volume\\.beta\\.kubernetes\\.io)/|^kubectl\\.kubernetes\\.io/last-applied-configuration$") | not)))}
     | with_entries(select(.value != null))),
   spec: (.spec | {accessModes, resources, volumeMode}
     + {storageClassName: $class, volumeName: $pv})}' <<<"$OLD_JSON" | k create -f - >/dev/null

for _ in $(seq 60); do
  [[ $(k get pvc "$PVC" -o jsonpath='{.status.phase}') == Bound ]] && break
  sleep 2
done
[[ $(k get pvc "$PVC" -o jsonpath='{.status.phase}') == Bound ]] || { echo "new PVC not Bound" >&2; exit 1; }

# Delete again once bound, so the volume is cleaned up with its claim later.
$KUBECTL patch pv "$NEW_PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}' >/dev/null
log "done: $PVC on $TARGET_CLASS ($NEW_PV), old PV $OLD_PV kept as Retain"
