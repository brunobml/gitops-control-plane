.PHONY: all setup push test bootstrap teardown status password help

all: help

help:
	@echo "Multi-Cluster Hub-and-Spoke Lab Commands:"
	@echo "  make setup      - Provision Moto, k3d clusters (hub, spoke-nonprod, spoke-prod), Argo CD, Kro & ACK"
	@echo "  make push       - Push all 3 repositories to GitHub (origin main)"
	@echo "  make bootstrap  - Apply root-control-plane Argo CD application to Hub"
	@echo "  make password   - Print Argo CD web UI admin password"
	@echo "  make test       - Run end-to-end smoke tests across Hub, Spokes, and Moto Cloud"
	@echo "  make status     - Inspect cluster statuses, pods, and AWS SQS queues"
	@echo "  make teardown   - Destroy all k3d clusters, Moto container, and network"

password:
	@echo -n "Argo CD Admin Password: "
	@kubectl --context k3d-hub-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""

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
