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
