.PHONY: orphans all setup start stop push test bootstrap teardown status password open-argocd open-headlamp open-dev open-test open-prod rotate-spoke-tokens promote-blueprints help

ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)

all: help

help:
	@echo "Multi-Cluster Hub-and-Spoke Lab Commands:"
	@echo "  make setup               - Provision Moto, k3d clusters (hub, spoke-nonprod, spoke-prod), Traefik, Argo CD, Headlamp, Kro & ACK"
	@echo "  make start               - Resume Moto and all k3d clusters after host reboot"
	@echo "  make stop                - Gracefully stop Moto and k3d clusters (preserving state)"
	@echo "  make build-app           - Build & push orders-processor container image to local registry (TAG=v1.0.0)"
	@echo "  make push                - Push all repositories to GitHub (origin main)"
	@echo "  make bootstrap           - Apply root-control-plane Argo CD application to Hub"
	@echo "  make post-bootstrap      - After bootstrap: worker credentials, adopt argo-cd, resync, smoke test"
	@echo "  make orphans               - Report (dry run) what deregistered tenant apps left behind; post-bootstrap removes it"
	@echo "  make rotate-spoke-tokens - Rotate 30-day TokenRequest tokens for Argo CD spokes and Headlamp"
	@echo "  make promote-blueprints  - Annotate spoke cluster secrets with revisions from clusters/blueprint-revisions.env"
	@echo "  make password            - Print Argo CD web UI admin password"
	@echo "  make open-argocd         - Open Argo CD Web UI (http://localhost:8080)"
	@echo "  make open-headlamp       - Open Headlamp Multi-Cluster Dashboard (http://headlamp.localhost:8080)"
	@echo "  make open-dev            - Port-forward Orders DEV web dashboard to http://localhost:8001"
	@echo "  make open-test           - Port-forward Orders TEST web dashboard to http://localhost:8002"
	@echo "  make open-prod           - Port-forward Orders PROD web dashboard to http://localhost:8003"
	@echo "  make test                - Run end-to-end smoke tests across Hub, Spokes, and Moto Cloud"
	@echo "  make status              - Inspect cluster statuses, pods, and AWS SQS queues"
	@echo "  make teardown            - Destroy all k3d clusters, Moto container, and network"

TAG ?= v1.0.0

build-app:
	@echo "🔨 Building & pushing orders-processor:$(TAG)..."
	@bash $(REPOS_DIR)/orders-processor/build-and-push.sh $(TAG)

rotate-spoke-tokens:
	@echo "🔄 Rotating spoke TokenRequest tokens (30 days)..."
	@bash $(ROOT_DIR)/scripts/register-spokes.sh && bash $(ROOT_DIR)/addons/headlamp/setup-credentials.sh

promote-blueprints:
	@echo "🚀 Promoting blueprint revisions to spoke clusters..."
	@bash $(ROOT_DIR)/scripts/promote-blueprints.sh

open-argocd:
	@echo "🌐 Opening Argo CD Web UI at http://localhost:8080..."
	@xdg-open http://localhost:8080 2>/dev/null || sensible-browser http://localhost:8080 2>/dev/null || echo "Open http://localhost:8080 in your browser"

open-headlamp:
	@echo "🌐 Opening Headlamp Kubernetes Dashboard at http://headlamp.localhost:8080..."
	@xdg-open http://headlamp.localhost:8080 2>/dev/null || sensible-browser http://headlamp.localhost:8080 2>/dev/null || echo "Open http://headlamp.localhost:8080 in your browser"

open-dev:
	@echo "🌐 Exposing DEV Orders Dashboard on http://localhost:8001..."
	@kubectl --context k3d-spoke-nonprod -n orders-dev port-forward svc/orders-dev 8001:80

open-test:
	@echo "🌐 Exposing TEST Orders Dashboard on http://localhost:8002..."
	@kubectl --context k3d-spoke-nonprod -n orders-test port-forward svc/orders-test 8002:80

open-prod:
	@echo "🌐 Exposing PROD Orders Dashboard on http://localhost:8003..."
	@kubectl --context k3d-spoke-prod -n orders-prod port-forward svc/orders-prod 8003:80

password:
	@echo "Argo CD local account (the built-in 'admin' account is disabled):"
	@echo "  platform-admin : full access (break-glass; works without Keycloak)"
	@echo "Passwords are stored outside Git, readable only by you:"
	@echo "  $${GITOPS_LAB_SECRET_DIR:-$$HOME/.config/gitops-lab}/argocd-<account>.password"
	@echo "To (re)set them: bash $(ROOT_DIR)/scripts/setup-argocd-accounts.sh"
	@echo ""
	@echo "Single sign-on (Keycloak realm 'lab', Phase 4): 'Log in via Keycloak' in Argo CD; Headlamp redirects"
	@echo "  platform-user  : group lab-platform-admins (Argo CD admin, Headlamp)"
	@echo "  tenant-a-user  : group lab-tenant-a (Argo CD tenant-a role, Headlamp)"
	@echo "  passwords      : $${GITOPS_LAB_SECRET_DIR:-$$HOME/.config/gitops-lab}/keycloak-<user>.password"
	@echo "  Keycloak admin : http://keycloak.localhost:8080/admin/ (user kc-admin, keycloak-admin.password)"
	@echo "  Switch user    : Argo CD 'Log out' ends the Keycloak session; Headlamp: open http://headlamp.localhost:8080/oauth2/sign_out"
	@echo "  Break-glass    : the local platform-admin account above works even when Keycloak is down"

push:
	@bash $(ROOT_DIR)/scripts/push-all.sh

start:
	@bash $(ROOT_DIR)/scripts/start-hub-spoke.sh

stop:
	@bash $(ROOT_DIR)/scripts/stop-hub-spoke.sh

setup:
	@bash $(ROOT_DIR)/scripts/setup-hub-spoke.sh

bootstrap:
	@kubectl --context k3d-hub-cluster apply -f $(ROOT_DIR)/bootstrap/argocd-hub-deployer.yaml
	@kubectl --context k3d-hub-cluster apply -f $(ROOT_DIR)/projects/ --validate=false
	@kubectl --context k3d-hub-cluster apply -f $(ROOT_DIR)/bootstrap/root-app.yaml --validate=false
	@echo "✔ Projects & Root application deployed to Hub Argo CD"

test:
	@bash $(ROOT_DIR)/scripts/smoke-test-hub-spoke.sh

status:
	@echo "=== HUB CLUSTER (Argo CD) ==="
	@kubectl --context k3d-hub-cluster -n argocd get applications,applicationsets 2>/dev/null || true
	@echo ""
	@echo "=== SPOKE NON-PROD (k3d-spoke-nonprod) ==="
	@kubectl --context k3d-spoke-nonprod get pods -A -l 'app.kubernetes.io/name in (sqs-chart,kro,orders-service)' 2>/dev/null || true
	@echo ""
	@echo "=== SPOKE PROD (k3d-spoke-prod) ==="
	@kubectl --context k3d-spoke-prod get pods -A -l 'app.kubernetes.io/name in (sqs-chart,kro,orders-service)' 2>/dev/null || true
	@echo ""
	@echo "=== CENTRAL MOTO CLOUD SQS QUEUES ==="
	@AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs list-queues --output table 2>/dev/null || echo "No queues found."

orphans:
	@bash $(ROOT_DIR)/scripts/orphans.sh --dry-run

post-bootstrap:
	@bash $(ROOT_DIR)/scripts/post-bootstrap.sh

teardown:
	@bash $(ROOT_DIR)/scripts/teardown-hub-spoke.sh
