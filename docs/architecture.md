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
- `juice-shop.yaml` deploys both the workload (`apps/juice-shop`) and its
  network policies (`policies/juice-shop`) as two sources.
- `selfHeal: true` + `prune: true` mean the cluster state always matches Git —
  if an attacker tampers with a live resource, ArgoCD reverts it.

## Defensive posture (the "defend" half of the loop)

| Control | File | Effect |
|---------|------|--------|
| Default-deny ingress+egress | `policies/juice-shop/default-deny.yaml` | Nothing flows unless allowed |
| DNS-only egress | `allow-dns.yaml` | Target can't pivot / exfiltrate |
| Port 3000 ingress only | `allow-ingress-3000.yaml` | Single attack surface |
| Pod Security: baseline | `namespace.yaml` | Blocks privileged pods |
| Dropped capabilities, non-root | `deployment.yaml` | Reduces blast radius |

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
