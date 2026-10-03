#!/usr/bin/env bash
# 2026-10-03 Track I.4 (owner decision O-7): the certificate Traefik presents on https://*.localhost.
#
# - Certificate and key live in ~/.config/gitops-lab/tls (dir 700, files 600); never in Git and
#   never printed. They reach the cluster as Secret traefik/local-tls (TLSStore "default").
# - Trusted path: mkcert. Once, on Windows: `winget install FiloSottile.mkcert` and `mkcert -install`
#   (adds a local CA to the Windows trust store used by Chrome/Edge). This script then calls
#   mkcert.exe through WSL interop (or a Linux `mkcert` sharing that CAROOT) to issue the leaf.
#   The CA key never leaves Windows.
# - Fallback without mkcert (review remark R-12): a self-signed certificate, so the Secret always
#   exists and Traefik starts without errors. Browsers warn once; HTTPS still redirects to HTTP.
#   The fallback is replaced automatically as soon as mkcert is available.
# - The certificate's notAfter goes to monitoring/credential-expiry (credential "local-tls"), so
#   SpokeTokenExpiringSoon warns 7 days before it expires. Renewed here when < 30 days are left.
# Idempotent; called by setup-hub-spoke.sh (after Traefik) and post-bootstrap.sh.
set -euo pipefail

SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
TLS_DIR="${SECRET_DIR}/tls"
CRT="${TLS_DIR}/local-tls.crt"
KEY="${TLS_DIR}/local-tls.key"
HOSTS=(localhost argocd.localhost headlamp.localhost grafana.localhost keycloak.localhost)
H=(kubectl --context k3d-hub-cluster)
RENEW_DAYS=30

umask 077
mkdir -p "$TLS_DIR"
chmod 700 "$SECRET_DIR" "$TLS_DIR"

mkcert_cmd() {
  if command -v mkcert >/dev/null 2>&1; then echo mkcert; return; fi
  if command -v mkcert.exe >/dev/null 2>&1; then echo mkcert.exe; return; fi
  local w
  # Look mkcert up on the *persistent* Windows PATH: WSL keeps the PATH from its own start, so a
  # fresh `winget install` would otherwise stay invisible until WSL restarts.
  w=$(powershell.exe -NoProfile -Command '$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User"); (Get-Command mkcert -ErrorAction SilentlyContinue).Source' 2>/dev/null | tr -d '\r' || true)
  if [[ -n "$w" ]]; then wslpath -u "$w"; fi
  return 0   # prints nothing when mkcert is not installed
}

is_fallback() { openssl x509 -in "$CRT" -noout -issuer 2>/dev/null | grep -q 'lab self-signed fallback'; }

needs_new() {
  [[ -s "$CRT" && -s "$KEY" ]] || return 0
  openssl x509 -in "$CRT" -noout -checkend $(( RENEW_DAYS * 86400 )) >/dev/null || return 0
  local san h
  san=$(openssl x509 -in "$CRT" -noout -ext subjectAltName 2>/dev/null)
  for h in "${HOSTS[@]}"; do [[ "$san" == *"DNS:${h}"* ]] || return 0; done
  if is_fallback && [[ -n "$(mkcert_cmd)" ]]; then return 0; fi
  return 1
}

if needs_new; then
  tmp=$(mktemp -d "${TLS_DIR}/.new.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  mk=$(mkcert_cmd)
  if [[ -n "$mk" ]]; then
    out_c="$tmp/c.pem"; out_k="$tmp/k.pem"
    [[ "$mk" == *.exe || "$mk" == /mnt/* ]] && { out_c=$(wslpath -w "$out_c"); out_k=$(wslpath -w "$out_k"); }
    "$mk" -cert-file "$out_c" -key-file "$out_k" "${HOSTS[@]}" >/dev/null 2>&1
    echo "  ✔ issued a certificate from the mkcert CA for ${HOSTS[*]}"
  else
    san=$(printf 'DNS:%s,' "${HOSTS[@]}"); san=${san%,}
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=lab self-signed fallback" \
      -addext "subjectAltName=${san}" -keyout "$tmp/k.pem" -out "$tmp/c.pem" >/dev/null 2>&1
    echo "  ! mkcert not found: issued a self-signed fallback (browsers warn once). Install mkcert on"
    echo "    Windows and run 'mkcert -install', then run this script again (scripts/setup-local-tls.sh)."
  fi
  install -m 600 "$tmp/c.pem" "$CRT"
  install -m 600 "$tmp/k.pem" "$KEY"
fi

"${H[@]}" get namespace traefik >/dev/null 2>&1 || "${H[@]}" create namespace traefik >/dev/null
"${H[@]}" -n traefik create secret tls local-tls --cert="$CRT" --key="$KEY" --dry-run=client -o yaml \
  | "${H[@]}" label --local -f - -o yaml app.kubernetes.io/managed-by=setup-local-tls app.kubernetes.io/part-of=gitops-lab \
  | "${H[@]}" apply -f - >/dev/null

not_after=$(date -d "$(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2)" +%s)
"${H[@]}" get namespace monitoring >/dev/null 2>&1 || "${H[@]}" create namespace monitoring >/dev/null
"${H[@]}" -n monitoring create configmap credential-expiry --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null 2>&1 || true
"${H[@]}" -n monitoring patch configmap credential-expiry --type merge -p "{\"data\":{\"local-tls\":\"${not_after}\"}}" >/dev/null

kind=trusted; is_fallback && kind="self-signed fallback"
echo "✔ Secret traefik/local-tls applied (${kind}; expires $(date -u -d @"$not_after" +%F); files in ${TLS_DIR}, mode 600)"
