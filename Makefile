CLUSTER       := secure-lab
ARGOCD_VER    := v2.12.4
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

verify-netpol: ## Prove egress is locked down (should FAIL to reach the internet)
	@echo "==> Attempting external egress from a juice-shop pod (expected: blocked)"
	-kubectl -n juice-shop exec deploy/juice-shop -- \
		sh -c 'wget -T 5 -qO- https://example.com >/dev/null 2>&1 && echo REACHABLE || echo BLOCKED'

down: ## Delete the cluster
	k3d cluster delete $(CLUSTER)
