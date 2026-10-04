#!/usr/bin/env bash
# Tenant IaC P0 spike: a throwaway k3d cluster (iac-spike) + its own moto (moto-spike on 127.0.0.1:5001).
# It never touches the lab (hub, spokes, moto-cloud).
#
#   spike.sh up       create cluster + moto, install kro + ACK ec2/iam/eks, apply network + RGD
#   spike.sh claims   apply the three test claims (team-data dev/prod, team-web dev)
#   spike.sh status   claims, ACK objects, records in moto per account
#   spike.sh recover  after a moto restart: fresh ACK credentials, re-create the network, re-adopt prod
#   spike.sh down     delete the cluster and moto-spike
#
# Needs: k3d, kubectl, helm, aws (CLI v2), jq, docker. KUBECONFIG is kept in ./.kubeconfig (git-ignored).
set -euo pipefail
cd "$(dirname "$0")"
export KUBECONFIG="$PWD/.kubeconfig"
MOTO_IMAGE=motoserver/moto@sha256:91fd602a21f49cf9eb82fdf474015a3c131d40104c8297ea6a2ca920708ae32c
E="--endpoint-url http://localhost:5001"

moto_as() { # credentials for one moto account via STS (moto has no access-key-per-account mapping)
  export AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x AWS_DEFAULT_REGION=us-east-1; unset AWS_SESSION_TOKEN
  local c; c=$(aws $E sts assume-role --role-arn "arn:aws:iam::$1:role/spike" --role-session-name spike --query Credentials --output json)
  export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$c") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$c") AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$c")
}

up() {
  k3d cluster create iac-spike --image rancher/k3s:v1.35.5-k3s1 --servers 1 --agents 0 --no-lb \
    --api-port 127.0.0.1:6559 --k3s-arg "--disable=traefik@server:0" --k3s-arg "--disable=metrics-server@server:0" --wait
  k3d kubeconfig get iac-spike > "$KUBECONFIG"; chmod 600 "$KUBECONFIG"
  docker run -d --name moto-spike --network k3d-iac-spike -p 127.0.0.1:5001:5000 \
    -e MOTO_ALLOW_NONEXISTENT_SERVICES=true -e MOTO_IAM_LOAD_MANAGED_POLICIES=true "$MOTO_IMAGE" -p5000 -H0.0.0.0 >/dev/null

  kubectl create ns kro; kubectl label ns kro pod-security.kubernetes.io/enforce=restricted
  helm install kro oci://registry.k8s.io/kro/charts/kro --version 0.9.4 -n kro \
    -f ../../../../platform-catalog/controllers/kro/values-kro.yaml
  kubectl create ns ack-system; kubectl label ns ack-system pod-security.kubernetes.io/enforce=restricted
  kubectl -n ack-system create secret generic ack-aws-creds \
    --from-literal=credentials=$'[default]\naws_access_key_id = mock-access-key-id\naws_secret_access_key = mock-secret'
  kubectl -n ack-system create configmap ack-role-account-map \
    --from-literal=111111111111=arn:aws:iam::111111111111:role/ack-sqs-controller \
    --from-literal=222222222222=arn:aws:iam::222222222222:role/ack-sqs-controller
  for s in ec2:1.21.2 iam:1.9.1 eks:1.23.1; do
    helm install "ack-${s%%:*}-controller" "oci://public.ecr.aws/aws-controllers-k8s/${s%%:*}-chart" \
      --version "${s##*:}" -n ack-system -f "values-${s%%:*}.yaml"
  done
  kubectl -n ack-system rollout status deploy --timeout=180s
  kubectl -n kro rollout status deploy --timeout=120s
  kubectl apply -f network.yaml
  kubectl apply -f kro-rbac.yaml -f rgd.yaml
}

claims() { kubectl apply -f instance-dev.yaml -f instance-prod.yaml -f instance-web.yaml; }

status() {
  kubectl get teamekscluster -A -o custom-columns='NS:.metadata.namespace,READY:.status.ready,CLUSTER:.status.clusterName,ARN:.status.clusterARN'
  kubectl get role.iam.services.k8s.aws,cluster.eks.services.k8s.aws,nodegroup -A \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status,TERMINAL:.status.conditions[?(@.type=="ACK.Terminal")].message'
  for a in 111111111111 222222222222; do
    moto_as "$a"
    echo "moto $a: clusters=[$(aws $E eks list-clusters --query clusters --output text)]" \
      "roles=[$(aws $E iam list-roles --query 'Roles[?starts_with(RoleName,`team-`)].RoleName' --output text)]"
  done
}

# After moto lost its state (restart). Found in P0:
#  1. ACK caches moto STS credentials per account; moto forgets them on restart and silently answers
#     as its default account 123456789012 -> restart the controllers for fresh credentials.
#  2. ACK EC2 does not recreate an InternetGateway/SecurityGroup whose ID is gone (InvalidXxx.NotFound),
#     so subnets/route table/clusters wait forever -> delete the network objects (retain: no AWS call)
#     and apply them again (in the lab: Argo CD self-heal re-creates them).
#  3. An adopted object whose record is gone fails with "adopted resource not found" -> drop the
#     services.k8s.aws/adopted marker; adopt-or-create then creates it again.
recover() {
  kubectl -n ack-system rollout restart deploy && kubectl -n ack-system rollout status deploy --timeout=180s
  kubectl -n platform-network delete vpc,subnet,internetgateway,routetable,securitygroup --all
  kubectl apply -f network.yaml
  kubectl get role.iam.services.k8s.aws,cluster.eks.services.k8s.aws,nodegroup -A \
    -o jsonpath='{range .items[?(@.metadata.annotations.services\.k8s\.aws/adopted=="true")]}{.kind}{" "}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
  while read -r kind ns name; do
    case "$kind" in Role) k=role.iam.services.k8s.aws ;; Cluster) k=cluster.eks.services.k8s.aws ;; *) k=nodegroup ;; esac
    kubectl -n "$ns" annotate "$k" "$name" services.k8s.aws/adopted-
  done
}

down() { k3d cluster delete iac-spike; docker rm -f moto-spike >/dev/null; rm -f "$KUBECONFIG"; }

"${1:?usage: spike.sh up|claims|status|recover|down}"
