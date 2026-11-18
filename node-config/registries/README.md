# Registry mirrors (Zot)

Points containerd on both nodes at the in-cluster Zot (`k8s/config/zot`,
CNP-295) for `ghcr.io` and `docker.io`. Zot pulls from GHCR with its own token
and from Docker Hub through `mirror.gcr.io`, and caches on the RGW.

k3s always keeps the upstream registry as the last endpoint: if Zot is down,
unreachable or does not have the image, containerd pulls from `ghcr.io` or
`registry-1.docker.io` directly. Do not set `disable-default-registry-endpoint`.
An image that is in neither Zot nor reachable upstream cannot be pulled.

`10.43.0.50` is Zot's fixed ClusterIP. containerd runs in the host network
namespace, where Cilium's socket LB translates ClusterIPs; host DNS cannot
resolve `zot.zot.svc`.

## Zot's own image

Zot's image is `ghcr.io/project-zot/zot`, so a pull of it goes to the mirror
first. It is pinned by digest with `IfNotPresent`, and step 2 puts it on both
nodes before the mirror exists, so a running node never pulls it through Zot.
If image GC removes it, the pull hits a Zot that is down, fails fast and falls
back to `ghcr.io`.

## Procedure

Not applied. Plan it in a window: restarting `k3s` on the server stops the API
for about a minute, running pods are not touched.

SSH as in `../k3s-server/README.md`; the worker is reached the same way.

1. Zot is synced and healthy in Argo CD, and answers from a node:

   ```bash
   curl -fsS http://10.43.0.50:5000/v2/ && echo ok
   ```

2. Zot's image is on both nodes:

   ```bash
   sudo k3s crictl pull ghcr.io/project-zot/zot:v2.1.23@sha256:9d3de83ac2099e6f4843045b4c9b65b7e8baf40f92d28f54906dee9d4d390fd7
   ```

3. Worker first (`k3s-worker-node`):

   ```bash
   sudo install -m 0644 /tmp/registries.yaml /etc/rancher/k3s/registries.yaml
   sudo systemctl restart k3s-agent
   sudo grep -A3 'host."http://10.43.0.50:5000"' /var/lib/rancher/k3s/agent/etc/containerd/certs.d/ghcr.io/hosts.toml
   ```

4. Check a pull through Zot from the worker:

   ```bash
   sudo k3s crictl pull docker.io/library/redis:7.4
   kubectl -n zot logs deploy/zot | grep -i 'docker.io/library/redis'
   ```

   A private image needs no credentials on the node: `sudo k3s crictl pull
   ghcr.io/3-istor/imports/epitweet/user-service:<tag>`.

5. Server (`my-k3s-cluster-node`): same as step 3 with `systemctl restart k3s`.

6. Fallback test: `kubectl -n zot scale deploy/zot --replicas=0`, then roll a
   tenant Deployment whose image is not on the node yet. The pod starts, pulled
   from GHCR. Scale Zot back to 1.

7. Redeploy EpiTweet and check the Zot log lists its `ghcr.io/3-istor/imports/epitweet/*`
   pulls (ticket acceptance).

## Rollback

On each node: `sudo rm /etc/rancher/k3s/registries.yaml`, then restart
`k3s-agent` or `k3s`. Images already pulled stay on the nodes.
