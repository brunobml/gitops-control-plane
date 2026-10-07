.PHONY: maintain local-tls test-docs sandbox-up sandbox-down sandbox-status test-lab1 ci ci-tenants ci-catalog ci-charts ci-schemas test-alert-rules orphans all setup start stop push test test-bats bootstrap teardown status password open-argocd open-headlamp open-dev open-test open-prod rotate-spoke-tokens promote-blueprints moto-restart restart-moto list-moto-resources moto-resources help

ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)

all: help

help:
	@echo "Multi-Cluster Hub-and-Spoke Lab Commands:"
	@echo "  make setup               - Provision Moto, k3d clusters (hub, spoke-nonprod, spoke-prod), Traefik, Argo CD (kro, ACK, Headlamp, ... follow from Git after bootstrap)"
	@echo "  make start               - Resume Moto and all k3d clusters after host reboot"
	@echo "  make stop                - Gracefully stop Moto and k3d clusters (preserving state)"
	@echo "  make moto-restart        - Gracefully restart Moto Cloud with zero-leak recovery & smoke test"
	@echo "  make list-moto-resources - Inspect Moto Cloud resources across accounts (parallel, multi-account; ARGS supported)"
	@echo "  make moto-resources      - Alias for make list-moto-resources"
	@echo "  make test-docs           - Run the learner-facing doc examples against the lab (MODE=live-mutating: also the self-reverting ones)"
	@echo "  make sandbox-up          - Lab 1 sandbox: k3d cluster learn-sandbox with kro (WITH_MOTO=1: plus moto + ACK SQS); sandbox-down removes it"
	@echo "  make test-lab1           - Lab 1 end to end in a fresh sandbox (local only, about 3 min)"
	@echo "  make build-app           - Build & push orders-processor container image to local registry (TAG=v1.0.0)"
	@echo "  make push                - Push all repositories to GitHub (origin main)"
	@echo "  make bootstrap           - Apply root-control-plane Argo CD application to Hub"
	@echo "  make post-bootstrap      - After bootstrap: worker credentials, adopt argo-cd, resync, smoke test"
	@echo "  make test-alert-rules      - promtool unit tests for the hub alert rules"
	@echo "  make maintain             - Routine upkeep: renew tokens (< 7 days left), clean up orphans; skips if the lab is stopped"
	@echo "  make local-tls            - (Re)issue the https://*.localhost certificate (mkcert if installed) and load it into Traefik"
	@echo "  make ci                   - Track A CI for this repo: offline render of all Applications, kubeconform, promtool, shellcheck, secret scan"
	@echo "  make ci-tenants / ci-catalog / ci-charts - Same checks the other repos run in GitHub (uses ../<repo>)"
	@echo "  make ci-schemas           - Regenerate ci/schemas/ (CRD JSON schemas) from the lab clusters after an upgrade"
	@echo "  make orphans               - Report (dry run) what deregistered tenant apps left behind; post-bootstrap removes it"
	@echo "  make rotate-spoke-tokens - Rotate 30-day TokenRequest tokens for Argo CD spokes and Headlamp"
	@echo "  make promote-blueprints  - Annotate spoke cluster secrets with revisions from clusters/blueprint-revisions.env"
	@echo "  make password            - Print Argo CD web UI admin password"
	@echo "  make open-argocd         - Open Argo CD Web UI (http://localhost)"
	@echo "  make open-headlamp       - Open Headlamp Multi-Cluster Dashboard (http://headlamp.localhost)"
	@echo "  make open-dev            - Port-forward Orders DEV web dashboard to http://localhost:8001"
	@echo "  make open-test           - Port-forward Orders TEST web dashboard to http://localhost:8002"
	@echo "  make open-prod           - Port-forward Orders PROD web dashboard to http://localhost:8003"
	@echo "  make test                - Run end-to-end Bats smoke tests across Hub, Spokes, and Moto Cloud (ARGS supported)"
	@echo "  make test-bats           - Alias for make test"
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
	@echo "🌐 Opening Argo CD Web UI at http://localhost..."
	@xdg-open http://localhost 2>/dev/null || sensible-browser http://localhost 2>/dev/null || echo "Open http://localhost in your browser"

open-headlamp:
	@echo "🌐 Opening Headlamp Kubernetes Dashboard at http://headlamp.localhost..."
	@xdg-open http://headlamp.localhost 2>/dev/null || sensible-browser http://headlamp.localhost 2>/dev/null || echo "Open http://headlamp.localhost in your browser"

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
	@echo "  Keycloak admin : http://keycloak.localhost/admin/ (user kc-admin, keycloak-admin.password)"
	@echo "  Switch user    : Argo CD 'Log out' ends the Keycloak session; Headlamp: open http://headlamp.localhost/oauth2/sign_out"
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
	@bash $(ROOT_DIR)/scripts/smoke-test-hub-spoke-bats.sh $(ARGS)

test-bats: test

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

test-alert-rules:
	@d=$$(mktemp -d) && helm template prometheus prometheus-community/prometheus --version 29.35.0 -n monitoring \
	  -f $(ROOT_DIR)/addons/observability/values-prometheus-hub.yaml \
	  | yq 'select(.kind=="ConfigMap" and .metadata.name=="prometheus-server") | .data["alerting_rules.yml"]' > $$d/alerting_rules.yml \
	  && cp $(ROOT_DIR)/addons/observability/alert-rules.test.yaml $$d/ && chmod 755 $$d && chmod 644 $$d/* \
	  && docker run --rm --entrypoint promtool -v $$d:/t -w /t \
	     quay.io/prometheus/prometheus@sha256:efd719c99d83b060d9daefdcf00360461adf279f45ef5391f8d111892118753e \
	     test rules alert-rules.test.yaml; rc=$$?; rm -rf $$d; exit $$rc

orphans:
	@bash $(ROOT_DIR)/scripts/orphans.sh --dry-run

post-bootstrap:
	@bash $(ROOT_DIR)/scripts/post-bootstrap.sh

test-docs:
	@bash $(ROOT_DIR)/tests/test_doc_examples.sh $(if $(filter live-mutating,$(MODE)),--mutating,)

moto-restart:
	@bash $(ROOT_DIR)/scripts/moto-restart.sh

restart-moto: moto-restart

# Lab 1 sandbox (learner on-ramp Track B): a disposable k3d cluster with kro, apart from the lab.
sandbox-up:
	@bash $(ROOT_DIR)/scripts/learning-sandbox.sh up $(if $(filter 1 true yes,$(WITH_MOTO)),--with-moto,)

sandbox-down:
	@bash $(ROOT_DIR)/scripts/learning-sandbox.sh down

sandbox-status:
	@bash $(ROOT_DIR)/scripts/learning-sandbox.sh status

test-lab1:
	@bash $(ROOT_DIR)/tests/test-lab1.sh

list-moto-resources:
	@bash $(ROOT_DIR)/scripts/list-moto-resources.sh $(ARGS)

moto-resources: list-moto-resources

teardown:
	@bash $(ROOT_DIR)/scripts/teardown-hub-spoke.sh

# 2026-10-03 Track A: the checks GitHub Actions runs, locally (see ci/README.md).
ci:
	@bash $(ROOT_DIR)/ci/check-control-plane.sh

ci-tenants:
	@TENANT_WORKLOADS_DIR=$(REPOS_DIR)/tenant-workloads bash $(ROOT_DIR)/ci/check-tenant-workloads.sh

ci-iac:
	@TENANT_IAC_DIR=$(REPOS_DIR)/tenant-iac bash $(ROOT_DIR)/ci/check-tenant-iac.sh

ci-catalog:
	@PLATFORM_CATALOG_DIR=$(REPOS_DIR)/platform-catalog bash $(ROOT_DIR)/ci/check-catalog.sh

ci-charts:
	@PLATFORM_CHARTS_DIR=$(REPOS_DIR)/platform-charts bash $(ROOT_DIR)/ci/check-charts.sh

ci-schemas:
	@python3 $(ROOT_DIR)/ci/update-crd-schemas.py

local-tls:
	@bash $(ROOT_DIR)/scripts/setup-local-tls.sh

maintain:
	@bash $(ROOT_DIR)/scripts/maintain.sh
