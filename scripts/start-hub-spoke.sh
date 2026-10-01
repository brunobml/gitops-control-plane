#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " Starting Multi-Cluster Hub-and-Spoke Lab Environment"
echo "=========================================================="

# 1. Verify Docker Daemon is accessible
if ! docker info >/dev/null 2>&1; then
  echo "❌ Error: Docker daemon is not running or not accessible."
  echo "   Try starting Docker with:"
  echo "     sudo systemctl start docker"
  echo "   or check status with:"
  echo "     systemctl status docker"
  exit 1
fi
echo "✔ Docker daemon is running"

# 2. Start Moto Cloud
echo "☁ Starting central Moto mock AWS container (moto-cloud)..."
if docker ps -a --format '{{.Names}}' | grep -q '^moto-cloud$'; then
  docker start moto-cloud >/dev/null
  echo "✔ moto-cloud container started"
else
  echo "ℹ moto-cloud container not found; creating new instance..."
  docker run -d \
    --name moto-cloud \
    --network k3d-hub-spoke-net \
    -p 127.0.0.1:5000:5000 \
    motoserver/moto@sha256:91fd602a21f49cf9eb82fdf474015a3c131d40104c8297ea6a2ca920708ae32c >/dev/null
  echo "✔ moto-cloud container created and started on 127.0.0.1:5000"
fi

# 3. Start k3d clusters
CLUSTERS=("hub-cluster" "spoke-nonprod" "spoke-prod")
for CLUSTER in "${CLUSTERS[@]}"; do
  if k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
    echo "☸ Starting k3d cluster '$CLUSTER'..."
    k3d cluster start "$CLUSTER" >/dev/null
    echo "✔ Cluster '$CLUSTER' started"
  else
    echo "⚠ Warning: k3d cluster '$CLUSTER' not found. Run 'make setup' if initial provisioning is needed."
  fi
done

# 4. Wait for API servers
echo "⏳ Verifying cluster API responsiveness..."
for CONTEXT in "k3d-hub-cluster" "k3d-spoke-nonprod" "k3d-spoke-prod"; do
  echo -n "   Testing context '$CONTEXT'..."
  RETRIES=15
  while [ $RETRIES -gt 0 ]; do
    if kubectl --context "$CONTEXT" cluster-info >/dev/null 2>&1; then
      echo " connected!"
      break
    fi
    RETRIES=$((RETRIES - 1))
    sleep 2
  done
  if [ $RETRIES -eq 0 ]; then
    echo " ⚠ timed out waiting for $CONTEXT"
  fi
done

echo ""
echo "=========================================================="
echo "✔ Hub-and-Spoke Lab environment started successfully!"
echo "  Run 'make status' to inspect running pods and queues."
echo "  Run 'make test' to run full end-to-end smoke verification."
echo "=========================================================="
