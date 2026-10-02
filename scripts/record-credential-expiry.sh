#!/usr/bin/env bash
# Phase 5 B.1: record a token's expiry (JWT `exp`, epoch seconds) in the hub ConfigMap
# monitoring/credential-expiry, which the credential-expiry exporter serves to Prometheus.
# usage: record-credential-expiry.sh <credential-name>   (token on stdin; only `exp` is kept)
set -euo pipefail
name=$1
exp=$(python3 -c 'import sys,json,base64; p=sys.stdin.read().strip().split(".")[1]; p+="="*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p))["exp"])')
H=(kubectl --context k3d-hub-cluster)
"${H[@]}" create namespace monitoring --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null
"${H[@]}" -n monitoring create configmap credential-expiry --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null 2>&1 || true
"${H[@]}" -n monitoring patch configmap credential-expiry --type merge -p "{\"data\":{\"${name}\":\"${exp}\"}}" >/dev/null
