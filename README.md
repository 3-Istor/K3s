# Apply kube Config

```bash
kustomize build k8s/ --enable-helm | kubectl apply --server-side --force-conflicts -f -
```

# Get Base64 data:
```bash
kubectl get secret argocd-initial-admin-secret  -n argocd -o json | jq '.data | map_values(@base64d)'
```

# Required tools:
- kubectl
- kustomize
- [kubelogin](https://github.com/int128/kubelogin)


# Kubeconfig

In order to access the K3s cluster using kubectl, you need to set up your kubeconfig file like bellows
```yaml
# ~/.kube/config
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://127.0.0.1:6443
    certificate-authority-data: <fixme>
  name: 3istor-cluster
contexts:
- context:
    cluster: 3istor-cluster
    user: oidc-user
  name: 3istor
current-context: 3istor
users:
- name: oidc-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubectl
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=https://auth.3istor.com/realms/3istor
      - --oidc-client-id=k3s-cluster
      - --oidc-extra-scope=profile,email,groups
```

# SSH Config
Don't forget to add the local port forwards for the Kubernetes API servers in your SSH config to access the cluster from your local machine.
```bash
# ~/.ssh/config
Host pae-node-1
    Hostname 10.0.0.1
    User pae-node-1
    Port 22
    IdentityFile ~/.ssh/my_private_key

    LocalForward 8080 192.168.1.210:80     # Horizon
    LocalForward 5000 192.168.1.210:5000   # Keystone
    LocalForward 8774 192.168.1.210:8774   # Nova API
    LocalForward 9696 192.168.1.210:9696   # Neutron API
    LocalForward 9292 192.168.1.210:9292   # Glance API
    LocalForward 9876 192.168.1.210:9876   # LoadBalancer Octavia
    LocalForward 6443 192.168.1.212:6443   # K3s main API Server
    LocalForward 6444 192.168.1.217:6443   # K3s lab API Server
```

# Just-in-time access and break-glass

Nobody holds standing access to project secrets in Vault or to cluster-admin
(CNP-124). A member of `infra` asks for it in the CMP (Platform, Elevated
access) with a reason and a duration; another member of `infra` approves; the
CMP adds the requester to the Keycloak group and removes them at expiry.

| Elevation    | Keycloak group        | Grants                                                         |
| ------------ | --------------------- | -------------------------------------------------------------- |
| `vault-data` | `elevated-vault-data` | Vault policy `vault_data_admin`: every `project-*` secret       |
| `k3s-admin`  | `elevated-k3s-admin`  | `cluster-admin` through `oidc-admin-binding`                    |

At rest, `infra` keeps `vault-admin` minus project secret values (list only)
and the cluster-wide `view` role (no Secrets).

After approval, log in again: `vault login -method=oidc`, and for kubectl
drop the cached token (`kubectl oidc-login clean`). After expiry or an early
end, tokens already issued keep the groups until they expire: 5 minutes for
the `k3s-cluster` client, at most 1 hour for a Vault OIDC token (TTL 15
minutes, max 1 hour, renewals do not re-read the groups).

The CMP removes, journals and reports on Discord anyone it finds in an
`elevated-*` group without an active grant (every 30 s), and the Loki rule
`KeycloakElevatedGroupChangedOutsideCmp` fires when such a change is not made
by the CMP. Adding a cloud admin role later: a new `elevated-<name>` group
here, bound to the role, and one catalogue entry in the CMP
(`backend/app/services/access/catalog.py`).

Break-glass, when the CMP or Keycloak cannot grant access:

- Keycloak up, CMP down: the Keycloak master admin (offline vault) adds the
  person to the `elevated-*` group in the 3istor realm. The Loki rule fires,
  which is expected; remove the member by hand afterwards, or the CMP removes
  them as soon as it is back.
- Keycloak down, cluster: SSH to the K3s server node and use
  `/etc/rancher/k3s/k3s.yaml` (client certificate, cluster-admin).
- Keycloak down, Vault: generate a root token from the unseal key shares kept
  in the offline vault (`vault operator generate-root`), revoke it when done.
  `VaultRootTokenUsed` fires.
