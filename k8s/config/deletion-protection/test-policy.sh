#!/usr/bin/env bash
# Probes cnp-deletion-protection on the current kubectl context (policy and CRDs must exist).
# Creates cnp209-probe-<ts>-* namespaces, Applications, AppProjects, CNPG Clusters and ObjectBucketClaims, then removes them.
set -u
P=cnp209-probe-$(date +%s)
L=cnp.3istor.com/deletion-protected
APP=--as=system:serviceaccount:argocd:argocd-application-controller
APPSET=--as=system:serviceaccount:argocd:argocd-applicationset-controller
# system:masters bypasses RBAC, so a denial can only come from the policy.
CMP="--as=system:serviceaccount:arcl-cmp:arcl-cmp --as-group=system:masters"
OTHER="--as=system:serviceaccount:default:other --as-group=system:masters"
M=cnp.3istor.com/move-cleanup
bad=0

# mk <apiVersion> <kind> <name> <namespace> <label value|-> <spec|->
mk() {
  { printf 'apiVersion: %s\nkind: %s\nmetadata:\n  name: %s\n' "$1" "$2" "$3"
    [ "$5" != - ] && printf '  labels:\n    %s: "%s"\n' "$L" "$5"
    [ "$6" != - ] && printf 'spec: %s\n' "$6"; } | kubectl create -n "$4" -f -
}

# check <allow|deny> <description> <command...>; a deny must come from the policy itself
check() {
  want=$1 name=$2; shift 2
  out=$("$@" 2>&1); rc=$?
  if { [ "$want" = allow ] && [ $rc = 0 ]; } || { [ "$want" = deny ] && [ $rc != 0 ] && [[ $out == *cnp-deletion-protection* ]]; }; then
    echo "PASS  $want  $name"
  else
    echo "FAIL  $want  $name: $out"; bad=1
  fi
}

# Same cases for namespaces, Applications and AppProjects.
run() { # run <apiVersion> <kind> <resource> <namespace> <spec|->
  local api=$1 kind=$2 res=$3 ns=$4 spec=$5 n=$P-${2,,} x who
  local k="kubectl -n $ns"
  for x in t:true f:false u:- a:true s:true e:-; do
    check allow "$kind create ${x%:*} (label ${x#*:})" mk "$api" "$kind" "$n-${x%:*}" "$ns" "${x#*:}" "$spec"
  done
  check deny  "$kind delete, label true"                $k delete "$res" "$n-t" --wait=false
  check allow "$kind delete, label false"               $k delete "$res" "$n-f" --wait=false
  check allow "$kind delete, no label"                  $k delete "$res" "$n-u" --wait=false
  check deny  "$kind remove label as admin"             $k label "$res" "$n-t" $L-
  check deny  "$kind set label false as admin"          $k label "$res" "$n-t" $L=false --overwrite
  check allow "$kind other label, label stays true"     $k label "$res" "$n-t" extra=1
  check allow "$kind annotation, label stays true"      $k annotate "$res" "$n-t" extra=1
  check deny  "$kind delete after other label"          $k delete "$res" "$n-t" --wait=false
  check allow "$kind enable protection as admin"        $k label "$res" "$n-e" $L=true
  check deny  "$kind delete after enabling"             $k delete "$res" "$n-e" --wait=false
  check allow "$kind remove label as application-controller"       $k label "$res" "$n-a" $L- $APP
  # Upstream Argo CD RBAC gives the applicationset-controller write access to Applications only.
  [ "$kind" = Application ] && who=$APPSET || who=$APP
  check allow "$kind set false as ${who#--as=system:serviceaccount:argocd:}" $k label "$res" "$n-s" $L=false --overwrite $who
  check allow "$kind delete after Argo CD removed the label"       $k delete "$res" "$n-a" --wait=false
}

# Argo CD flips the label, then the objects can go.
cleanup() {
  local r o
  for r in namespaces "applications.argoproj.io argocd" "appprojects.argoproj.io argocd"; do
    set -- $r
    for o in $(kubectl get "$1" ${2:+-n "$2"} -o name | grep "/$P-"); do
      kubectl label "$o" ${2:+-n "$2"} $L=false --overwrite $APP >/dev/null
      kubectl delete "$o" ${2:+-n "$2"} --wait=false >/dev/null
    done
  done
}
trap cleanup EXIT

run v1 Namespace namespaces default -
run argoproj.io/v1alpha1 Application applications.argoproj.io argocd \
  '{project: default, destination: {server: "https://kubernetes.default.svc", namespace: default}, source: {repoURL: "https://example.invalid/r.git", path: .}}'
run argoproj.io/v1alpha1 AppProject appprojects.argoproj.io argocd '{}'

# CNPG Cluster and ObjectBucketClaim: only the namespace label matters, they have none of their own.
# The claim names no real StorageClass so no bucket is provisioned (ceph-bucket-retain would outlive it).
for x in t:true u:-; do
  check allow "Namespace db-${x%:*} create (label ${x#*:})" mk v1 Namespace "$P-db-${x%:*}" default "${x#*:}" -
  check allow "Cluster create in db-${x%:*}" mk postgresql.cnpg.io/v1 Cluster db "$P-db-${x%:*}" - '{instances: 1, storage: {size: 1Gi}}'
  check allow "ObjectBucketClaim create in db-${x%:*}" mk objectbucket.io/v1alpha1 ObjectBucketClaim bucket "$P-db-${x%:*}" - '{generateBucketName: probe, storageClassName: cnp-probe-none}'
done
check deny  "Cluster delete in namespace labelled true" kubectl -n "$P-db-t" delete clusters.postgresql.cnpg.io db --wait=false
check allow "Cluster delete in unlabelled namespace"    kubectl -n "$P-db-u" delete clusters.postgresql.cnpg.io db --wait=false
check deny  "ObjectBucketClaim delete in namespace labelled true" kubectl -n "$P-db-t" delete objectbucketclaims.objectbucket.io bucket --wait=false
check allow "ObjectBucketClaim delete in unlabelled namespace"    kubectl -n "$P-db-u" delete objectbucketclaims.objectbucket.io bucket --wait=false

# Project move: only the CMP sets the annotation, then only the CMP deletes the protected namespace.
for x in a:true b:true c:true d:true; do
  check allow "Namespace mv-${x%:*} create (label true)" mk v1 Namespace "$P-mv-${x%:*}" default true -
done
check deny  "move-cleanup annotation as admin"             kubectl annotate namespace "$P-mv-a" $M=true
check deny  "move-cleanup annotation as another user"      kubectl annotate namespace "$P-mv-a" $M=true $OTHER
check deny  "Namespace create with move-cleanup"           kubectl create -f - <<<"{apiVersion: v1, kind: Namespace, metadata: {name: $P-mv-x, annotations: {$M: 'true'}}}"
check deny  "delete as CMP without the annotation"         kubectl delete namespace "$P-mv-a" --wait=false $CMP
check allow "move-cleanup annotation as CMP"               kubectl annotate namespace "$P-mv-b" $M=true $CMP
check deny  "remove move-cleanup annotation as admin"      kubectl annotate namespace "$P-mv-b" $M- 
check deny  "delete annotated namespace as admin"          kubectl delete namespace "$P-mv-b" --wait=false
check deny  "delete annotated namespace as another user"   kubectl delete namespace "$P-mv-b" --wait=false $OTHER
check allow "delete annotated namespace as CMP"            kubectl delete namespace "$P-mv-b" --wait=false $CMP
# Objects of a namespace being cleaned up (the namespace controller deletes them) may go.
check allow "Namespace mv-db annotated as CMP" kubectl annotate namespace "$P-db-t" $M=true $CMP
check allow "Cluster delete in annotated namespace"     kubectl -n "$P-db-t" delete clusters.postgresql.cnpg.io db --wait=false
check allow "ObjectBucketClaim delete in annotated namespace" kubectl -n "$P-db-t" delete objectbucketclaims.objectbucket.io bucket --wait=false

[ $bad = 0 ] && echo "all checks passed"
exit $bad
