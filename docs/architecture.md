# Architecture & design decisions

## Why k3d (local) instead of EKS/GKE

This lab runs **entirely on local Docker** — no cloud bill. k3d packages k3s
(a certified, lightweight Kubernetes) inside Docker containers. A recruiter or
Upwork client can `make up` and reproduce the whole environment in ~2 minutes on
a laptop. That reproducibility is itself a portfolio asset.

When a project genuinely needs a managed control plane (e.g. demonstrating IRSA
on EKS), spin it up only for the demo, capture screenshots/Terraform, and
`terraform destroy` — keeping cloud cost near zero.

## GitOps with ArgoCD (app-of-apps)

- `bootstrap/argocd/root-app.yaml` is the single entry point.
- It watches `apps/argocd-apps/`, where each file is an ArgoCD `Application`.
- `juice-shop.yaml` renders our own Helm chart (`chart/`) — the workload **and**
  its security controls ship together as one release.
- `selfHeal: true` + `prune: true` mean the cluster state always matches Git —
  if an attacker tampers with a live resource, ArgoCD reverts it.

## Why our own Helm chart (not a third-party one)

Community Juice Shop charts are thin and don't carry the security controls that
are the whole point here. Authoring our own chart keeps default-deny, DNS-only
egress and pod security as first-class, parameterized values — and demonstrates
chart authoring (templates, `values.yaml`, `_helpers.tpl`), not just chart
consumption. Heavy off-the-shelf infra in later projects (Cilium, Falco,
kube-prometheus-stack) is consumed from upstream charts instead.

## Defensive posture (the "defend" half of the loop)

| Control | Where | Effect |
|---------|-------|--------|
| Default-deny ingress+egress | `chart` `networkPolicy.enabled` | Nothing flows unless allowed |
| DNS-only egress | `networkPolicy.dnsEgress` | Target can't pivot / exfiltrate |
| App-port ingress only | `networkPolicy.allowedIngressPort` | Single attack surface |
| Pod Security: baseline | `namespace.podSecurity` | Blocks privileged pods |
| Dropped capabilities, non-root | `securityContext` | Reduces blast radius |

Flip `networkPolicy.enabled: false` (see `chart/values-insecure.yaml`) to render
the wide-open "before" version for an insecure/secure comparison.

## Verifying the controls actually work

```bash
make verify-netpol   # confirms egress to the internet is BLOCKED
```

This is the kind of evidence to screenshot for the portfolio: a deliberately
vulnerable app that still cannot reach out of its namespace.

## What changes in later projects

- **#2 devsecops-pipeline** — scans these manifests (Checkov/tfsec) and the
  image (Trivy) in GitLab CI before they ever reach the cluster.
- **#5 runtime-security** — swaps k3s flannel for **Cilium** to get L7 network
  policies and Hubble visibility, plus Falco for syscall-level detection.
