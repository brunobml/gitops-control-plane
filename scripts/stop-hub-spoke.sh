#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " Stopping Multi-Cluster Hub-and-Spoke Lab Environment"
echo " (Preserving cluster state, volumes, and configurations)"
echo "=========================================================="

CLUSTERS=("hub-cluster" "spoke-nonprod" "spoke-prod")
for CLUSTER in "${CLUSTERS[@]}"; do
  if k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
    echo "☸ Stopping k3d cluster '$CLUSTER'..."
    k3d cluster stop "$CLUSTER" >/dev/null || true
    echo "✔ Cluster '$CLUSTER' stopped"
  fi
done

if docker ps -a --format '{{.Names}}' | grep -q '^moto-cloud$'; then
  echo "☁ Stopping moto-cloud container..."
  docker stop moto-cloud >/dev/null || true
  echo "✔ moto-cloud container stopped"
fi

echo ""
echo "=========================================================="
echo "✔ Hub-and-Spoke Lab environment stopped."
echo "  Run 'make start' to resume all clusters and services."
echo "=========================================================="
