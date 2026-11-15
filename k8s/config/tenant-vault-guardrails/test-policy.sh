#!/usr/bin/env bash
# Probes cnp-tenant-vault-secrets on the current kubectl context with server-side
# dry-runs only: nothing is created. The policy must be installed.
# Usage: test-policy.sh <project> <app>   (an existing project and one of its apps)
set -u
p=${1:?project} a=${2:?app}
bad=0

# probe <allow|deny> <namespace> <path> <role|-> <description>; a deny must come from the policy itself
probe() {
  local role=""
  [ "$4" != - ] && role="\"vaultRole\":\"$4\","
  out=$(printf '{"apiVersion":"ricoberger.de/v1alpha1","kind":"VaultSecret","metadata":{"name":"probe","namespace":"%s"},"spec":{%s"path":"%s","type":"Opaque"}}' "$2" "$role" "$3" \
    | kubectl create --dry-run=server -f - 2>&1)
  rc=$?
  if { [ "$1" = allow ] && [ $rc = 0 ]; } || { [ "$1" = deny ] && [ $rc != 0 ] && [[ $out == *cnp-tenant-vault-secrets* ]]; }; then
    echo "PASS  $1  $5"
  else
    echo "FAIL  $1  $5: $out"; bad=1
  fi
}

probe deny  "$p-$a" kvv2/arcl-cmp/credentials vault-secrets-operator-role "platform path with the operator's role"
probe deny  "$p-$a" "project-$p/$a" arcl-cmp-role                     "own path with a platform role"
probe deny  "$p-$a" "project-$p/$a" -                                 "no role, the operator's default"
probe deny  "$p-$a" "project-$p-x/$a" "$p-$a-role"                   "mount that only shares the project prefix"
probe deny  "$p-$a" "project-$p/../kvv2/arcl-cmp" "$p-$a-role"        "path climbing out of the mount"
probe deny  "$p-$a" "project-$p/$a" "$p-$a-staging-role"              "staging role in the prod namespace"
probe allow "$p-$a" "project-$p/$a" "$p-$a-role"                      "own path and role"
probe allow "$p-$a" "project-$p/system/registry" "project-$p-system-role" "project registry credential"
probe allow "$p-system" "project-$p/system/tunnel" "project-$p-system-role" "system namespace"
exit $bad
