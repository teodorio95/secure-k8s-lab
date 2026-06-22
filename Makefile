CLUSTER       := secure-lab
ARGOCD_VER    := v3.4.4
ARGOCD_NS     := argocd

.PHONY: help up down argocd argocd-pass argocd-ui juice-ui root-app verify-netpol

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

up: ## Create cluster, install ArgoCD, deploy the lab (zero cloud cost)
	k3d cluster create --config cluster/k3d-config.yaml
	$(MAKE) argocd
	@echo "==> Waiting for ArgoCD to be ready..."
	kubectl -n $(ARGOCD_NS) rollout status deploy/argocd-server --timeout=180s
	$(MAKE) root-app
	@echo ""
	@echo "Lab is up. Next:"
	@echo "  make argocd-pass   # admin password"
	@echo "  make argocd-ui     # https://localhost:8080"
	@echo "  make juice-ui      # http://localhost:3000"

argocd: ## Install ArgoCD into the cluster
	kubectl create namespace $(ARGOCD_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n $(ARGOCD_NS) \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VER)/manifests/install.yaml

root-app: ## Apply the app-of-apps (after pushing repo + editing repoURL)
	kubectl apply -f bootstrap/argocd/root-app.yaml

argocd-pass: ## Print the ArgoCD admin password
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

argocd-ui: ## Port-forward the ArgoCD UI to https://localhost:8080
	kubectl -n $(ARGOCD_NS) port-forward svc/argocd-server 8080:443

juice-ui: ## Port-forward Juice Shop to http://localhost:3000
	kubectl -n juice-shop port-forward svc/juice-shop 3000:3000

kyverno-reports: ## Show Kyverno policy reports (what Audit mode flagged)
	kubectl get clusterpolicy
	@echo ""
	kubectl get policyreport -A 2>/dev/null || echo "(no reports yet — give the background controller a minute)"

verify-netpol: ## Prove egress is locked down (should FAIL to reach the internet)
	@echo "==> Spinning up a labelled debug pod to test external egress (expected: BLOCKED)"
	@# The juice-shop image is distroless (no shell), so we use a labelled busybox
	@# pod that inherits the same NetworkPolicies (podSelector app=juice-shop).
	@kubectl -n juice-shop delete pod netcheck --ignore-not-found >/dev/null 2>&1
	@kubectl -n juice-shop run netcheck --image=busybox:1.36 --labels=app=juice-shop \
		--restart=Never --command -- sleep 60 >/dev/null
	@kubectl -n juice-shop wait --for=condition=Ready pod/netcheck --timeout=60s >/dev/null
	@printf "external egress (1.1.1.1:443): "
	@kubectl -n juice-shop exec netcheck -- sh -c \
		'nc -w 4 -z 1.1.1.1 443 && echo "REACHABLE — netpol NOT enforced" || echo "BLOCKED — egress denied (expected)"'
	@printf "cluster DNS (allowed): "
	@kubectl -n juice-shop exec netcheck -- sh -c \
		'nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 && echo "RESOLVES (expected)" || echo "FAILED"'
	@kubectl -n juice-shop delete pod netcheck --wait=false >/dev/null

down: ## Delete the cluster
	k3d cluster delete $(CLUSTER)
