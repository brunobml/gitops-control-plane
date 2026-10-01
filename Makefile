.PHONY: all setup push test bootstrap teardown status password open-argocd open-headlamp open-dev open-test open-prod rotate-spoke-tokens help

ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)

all: help

help:
	@echo "Multi-Cluster Hub-and-Spoke Lab Commands:"
	@echo "  make setup               - Provision Moto, k3d clusters (hub, spoke-nonprod, spoke-prod), Traefik, Argo CD, Headlamp, Kro & ACK"
	@echo "  make build-app           - Build & push orders-processor container image to local registry (TAG=v1.0.0)"
	@echo "  make push                - Push all repositories to GitHub (origin main)"
	@echo "  make bootstrap           - Apply root-control-plane Argo CD application to Hub"
	@echo "  make rotate-spoke-tokens - Rotate 30-day TokenRequest tokens for Argo CD spokes and Headlamp"
	@echo "  make password            - Print Argo CD web UI admin password"
	@echo "  make open-argocd         - Open Argo CD Web UI (http://localhost:8080)"
	@echo "  make open-headlamp       - Open Headlamp Multi-Cluster Dashboard (http://headlamp.localhost:8080)"
	@echo "  make open-dev            - Port-forward Tenant-A DEV web dashboard to http://localhost:8001"
	@echo "  make open-test           - Port-forward Tenant-A TEST web dashboard to http://localhost:8002"
	@echo "  make open-prod           - Port-forward Tenant-A PROD web dashboard to http://localhost:8003"
	@echo "  make test                - Run end-to-end smoke tests across Hub, Spokes, and Moto Cloud"
	@echo "  make status              - Inspect cluster statuses, pods, and AWS SQS queues"
	@echo "  make teardown            - Destroy all k3d clusters, Moto container, and network"

TAG ?= v1.0.0

build-app:
	@echo "🔨 Building & pushing orders-processor:$(TAG)..."
	@bash $(REPOS_DIR)/orders-processor/build-and-push.sh $(TAG)

rotate-spoke-tokens:
	@echo "🔄 Rotating spoke TokenRequest tokens (30 days)..."
	@bash scripts/register-spokes.sh && bash addons/headlamp/setup-credentials.sh

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
	@echo "Argo CD Admin Credentials:"
	@echo "  Username: admin"
	@echo "  Password: admin123"

push:
	@bash scripts/push-all.sh

setup:
	@bash scripts/setup-hub-spoke.sh

bootstrap:
	@kubectl --context k3d-hub-cluster apply -f projects/ --validate=false
	@kubectl --context k3d-hub-cluster apply -f bootstrap/root-app.yaml --validate=false
	@echo "✔ Projects & Root application deployed to Hub Argo CD"

test:
	@bash scripts/smoke-test-hub-spoke.sh

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

teardown:
	@bash scripts/teardown-hub-spoke.sh
