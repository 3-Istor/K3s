# Argo CD cluster registration

Argo CD is the **only** component holding credentials on remote clusters (D-02).
That makes this directory the single place a cluster becomes addressable, and the
single place those credentials must never appear.

## How it works

Each cluster is an Argo CD cluster Secret, materialised from Vault by the secrets
operator — the same mechanism `argocd-secret` and `cnp-portal-github-creds`
already use. Nothing here contains a token.

The Secret's `name` key is what Applications address. It must match the
`spec.targetCloud` value in the project registry exactly:

| Cluster | Secret name | `name` key | Vault path |
| --- | --- | --- | --- |
| On-prem | `cluster-onprem` | `onprem` | `kvv2/argocd/clusters/onprem` |
| AWS | `cluster-aws` | `aws` | `kvv2/argocd/clusters/aws` |
| GCP | `cluster-gcp` | `gcp` | `kvv2/argocd/clusters/gcp` |

Applications address `destination.name`, never `destination.server`: the URL
changes when a cluster is rebuilt, the name does not (D-03).

## Registering a new cluster

The cluster team provides the API server endpoint, the cluster CA, and a service
account token with the permissions Argo CD needs. Those three go into Vault:

```bash
# Values come from the cluster team. Never commit them, never echo them into a
# shell history you keep.
vault kv put kvv2/argocd/clusters/aws \
  name=aws \
  server=https://<api-server-endpoint> \
  config='{"bearerToken":"<token>","tlsClientConfig":{"insecure":false,"caData":"<base64-ca>"}}'
```

Then add the matching file to `../kustomization.yaml`. It is deliberately left
out until the Vault path exists — the operator would otherwise reconcile a
missing path and report an error every cycle.

Confirm the cluster is addressable before any project is pointed at it:

```bash
argocd cluster list          # the new name must appear
kubectl -n argocd get secret cluster-aws -o jsonpath='{.metadata.labels}'
```

## Why on-prem is registered explicitly

Argo CD has a built-in `in-cluster` destination, and the platform's own
`apps` Application still uses it. Projects do not: registering on-prem as
`onprem` means all three clusters are addressed identically, and the generated
Applications can use `spec.targetCloud` from the registry verbatim as their
destination.

The cost is that the local cluster is reachable under two names. If that
ambiguity ever causes confusion, `cluster.inClusterEnabled: false` in
`argocd-cm` removes the built-in one — but that also breaks the platform's own
Applications, so it is a separate, deliberate change and not part of this work.

## Decommissioning a cluster

Removing a cluster's Secret makes every Application targeting it fail to sync —
it does **not** delete anything on the cluster. Take the projects through
`cnp-clean --cloud <name>` first, then remove the registration. The order is in
the decommission runbook in `cnp-docs`.
