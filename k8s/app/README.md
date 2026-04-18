# ArgoCD Application Deployment Guide

## Best Practices with Kyverno

Because we're running Kyverno, deploying applications requires a few tweaks to prevent ArgoCD from getting stuck in a sync loop due to mutating webhooks.

### 1. Enable Server-Side Apply
When syncing, use Server-Side Apply instead of Client-Side. This lets the Kubernetes API handle resource merges properly.
- **Use**: `ServerSideApply=true`
- **Avoid**: `Replace=true` (this drops and recreates resources, which can cause downtime or break state)
- **Optional**: `CreateNamespace=true` if deploying to a fresh namespace.

### 2. Handle Mutating Webhooks (ServerSideDiff)
To prevent ArgoCD from reporting resources as `OutOfSync` every time Kyverno injects defaults or labels, you need to tell ArgoCD to calculate diffs server-side.

You can do this per-app via annotations:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/compare-options: ServerSideDiff=true,IncludeMutationWebhook=true
