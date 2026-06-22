# secure-k8s-lab

> Foundation of a DevSecOps portfolio: a reproducible Kubernetes lab, managed with GitOps (ArgoCD), where an intentionally vulnerable target (OWASP Juice Shop) is **deployed and locked down** — so it can be attacked and defended in a fully isolated environment.

This is project **#1** of a 5-part DevSecOps portfolio. It builds the platform everything else stands on:

| # | Project | Role |
|---|---------|------|
| **1** | **secure-k8s-lab** *(this repo)* | Reproducible cluster + GitOps + isolated vulnerable target |
| 2 | devsecops-pipeline | Scanning in CI (SAST/DAST/deps/IaC) |
| 3 | supply-chain-security | Image signing, SBOM, admission control |
| 4 | offensive-writeups | Documented attacks against this lab |
| 5 | runtime-security | Falco + Cilium detecting those attacks |

## The story this repo tells

> "I don't just run a vulnerable app. I run it on a GitOps-managed cluster, isolated with a default-deny network posture, where every change is declarative and auditable. I can attack it — and I built the cage around it."

## Architecture

```mermaid
flowchart LR
    subgraph attacker["Kali (Parallels VM)"]
        K[nmap / Burp / sqlmap]
    end
    subgraph cluster["k3d cluster: secure-lab"]
        subgraph argocd["argocd ns"]
            A[ArgoCD<br/>app-of-apps]
        end
        subgraph juice["juice-shop ns — default-deny"]
            J[Juice Shop :3000]
        end
        A -. GitOps sync .-> J
    end
    K -->|only :3000 allowed| J
    J -.x|egress blocked except DNS| internal[(rest of cluster)]
```

**Defensive posture baked in:**
- `default-deny` ingress **and** egress in the `juice-shop` namespace
- Only port `3000` ingress is allowed (the app), nothing else
- Egress allowed **only** to cluster DNS — the target cannot pivot to the rest of the cluster
- Everything is declarative and synced by ArgoCD (app-of-apps pattern)

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [k3d](https://k3d.io/) (`brew install k3d`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [helm](https://helm.sh/) (optional, for later projects)

## Quick start

```bash
make up            # create cluster + install ArgoCD + sync the lab
make argocd-pass   # print the ArgoCD admin password
make argocd-ui     # port-forward the ArgoCD UI -> https://localhost:8080
make juice-ui      # port-forward Juice Shop   -> http://localhost:3000
make down          # tear everything down
```

## How NetworkPolicies are actually enforced

k3d ships k3s, which includes an embedded NetworkPolicy controller (kube-router),
so the `default-deny` policies in [policies/](policies/) are **enforced for real** —
not silently ignored as they would be on a bare flannel setup. In project #5 we swap
the CNI for Cilium to add L7-aware policies and runtime visibility.

## Repository layout

```
secure-k8s-lab/
├── Makefile                     # lifecycle: up / down / ui / password
├── cluster/
│   └── k3d-config.yaml          # declarative cluster definition
├── bootstrap/
│   └── argocd/
│       └── root-app.yaml        # app-of-apps entry point
├── apps/
│   ├── argocd-apps/
│   │   └── juice-shop.yaml      # ArgoCD Application -> apps/juice-shop
│   └── juice-shop/
│       ├── namespace.yaml
│       ├── deployment.yaml
│       └── service.yaml
├── policies/
│   └── juice-shop/
│       ├── default-deny.yaml
│       ├── allow-dns.yaml
│       └── allow-ingress-3000.yaml
└── docs/
    └── architecture.md
```

## ⚠️ Legal / safety note

OWASP Juice Shop is **intentionally vulnerable** and is meant to be attacked.
Run it **only** inside this isolated lab. Never expose it to the public internet,
and only ever scan/attack targets you own or platforms explicitly built for it
(TryHackMe, Hack The Box, PortSwigger Web Security Academy).
