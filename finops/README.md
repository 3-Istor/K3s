# FinOps inputs

Versioned prices the CMP FinOps module and OpenCost read. A price change is a PR
with its effective date.

| File | What | Read by |
|---|---|---|
| `onprem-tco.yaml` | Cost of the on-prem cluster (energy, hardware, network) and of the GPU server | `tco` generator, CMP |
| `ai-prices.yaml` | Public prices of the models behind the AI gateway (D-F8) | CMP, source `ai_gateway` |
| `saas.yaml` | Subscriptions outside Kubernetes | CMP, source `saas` |

After editing `onprem-tco.yaml`, regenerate OpenCost's pricing:

```bash
go -C finops run ./tco
```

CI fails when `k8s/config/opencost/values-pricing.yaml` is out of date. Values
marked `mock: true` are placeholders; the CMP labels the costs built on them.
