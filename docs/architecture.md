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
- ArgoCD is pinned to **v3.4.4** (see `ARGOCD_VER` in the Makefile).

The root app syncs three things: the **Juice Shop** chart, **Kyverno** (upstream
chart), and our **Kyverno policy** pack.

> **Known cosmetic drift:** Kyverno's CRDs are huge and the API server fills in
> schema defaults, so the in-cluster ArgoCD controller reports the `kyverno` app
> `OutOfSync` under `ServerSideApply`, even though `argocd app diff kyverno --core`
> shows no real diff and `ignoreDifferences` is configured. The app stays
> **Healthy** and policies enforce — it's a documented ArgoCD + large-CRD quirk,
> not a deployment problem.

## Accessing the apps

Juice Shop is exposed via the cluster's **Traefik ingress** (`chart/templates/
ingress.yaml`) through the k3d loadbalancer container, so it's reachable
persistently at `http://localhost:8081` with no `kubectl port-forward`. This is
the difference between a *persistent container-backed endpoint* (ingress) and an
*ad-hoc client-side tunnel* (`make juice-ui` / `make argocd-ui`).

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

## Admission control with Kyverno (the enforcement backstop)

Two complementary control points enforce the same standards:

| Control point | Where | Strength | Weakness |
|---------------|-------|----------|----------|
| Shift-left scanning | CI (project #2) | Catches issues before merge | Can be bypassed (skip CI) |
| **Admission control** | **Kyverno (cluster)** | **Cannot be bypassed** | Runs only at apply time |

Defense in depth = both. Kyverno is installed from the upstream chart and
configured by our own `ClusterPolicy` pack in `policies/kyverno/`, showing all
three policy mechanisms:

- **validate** (`01`–`03`) — check & report/block: no `:latest`, run as non-root,
  require resource limits. Started in **Audit** mode (`validate.failureAction: Audit`).
- **mutate** (`04`) — auto-fill a hardened `securityContext` on pods that omit it,
  using the `+(...)` anchor (adds only if missing; never overrides).
- **generate** (`05`) — auto-create a default-deny `NetworkPolicy` in every new
  namespace (system namespaces excluded), so the network posture is automatic.

### Audit → Enforce rollout

Policies ship in **Audit** (report only, nothing blocked) so you can review
`make kyverno-reports` and confirm nothing legitimate would break. Once reports
are clean, flip `validate.failureAction` to **Enforce** to actively reject
violations. This is how you introduce policy without taking down running
workloads.

> Note: Pod Security Admission (the namespace labels in the chart) is the
> lightweight built-in baseline; Kyverno is the superset that expresses what PSA
> cannot (image tags, resource limits, mutation, generation).

## What changes in later projects

- **#2 devsecops-pipeline** — scans these manifests (Checkov/tfsec) and the
  image (Trivy) in GitLab CI before they ever reach the cluster.
- **#5 runtime-security** — swaps k3s flannel for **Cilium** to get L7 network
  policies and Hubble visibility, plus Falco for syscall-level detection.
