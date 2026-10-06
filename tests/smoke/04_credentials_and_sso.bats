#!/usr/bin/env bats
# tests/smoke/04_credentials_and_sso.bats

setup() {
  load "common.bash"
}

@test "Gate 8: Cluster and Headlamp credentials are valid and unexpired" {
  local rows=""
  for s in cluster-spoke-nonprod cluster-spoke-prod; do
    rows+="argocd/${s} $(jwt_exp_from_cluster_secret "$s")"$'\n'
  done
  while read -r user exp; do
    rows+="headlamp-secret/${user} ${exp}"$'\n'
  done < <(kubectl --context k3d-hub-cluster -n headlamp get secret headlamp-kubeconfig -o jsonpath='{.data.config}' | base64 -d | kubeconfig_exps)

  local headlamp_pod
  headlamp_pod=$(kubectl --context k3d-hub-cluster -n headlamp get pods -l app.kubernetes.io/name=headlamp \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$headlamp_pod" ]

  while read -r user exp; do
    rows+="headlamp-pod/${user} ${exp}"$'\n'
  done < <(kubectl --context k3d-hub-cluster -n headlamp exec "$headlamp_pod" -- cat /home/headlamp/.kube/config | kubeconfig_exps)

  local failed=0
  while read -r name exp; do
    [[ -z "$name" ]] && continue
    local remaining=$(( exp - NOW_EPOCH ))
    if (( remaining <= 0 )); then
      failed=1
    fi
  done <<< "$rows"

  [ "$failed" -eq 0 ]
}

@test "Gate 10a: OIDC issuer is identical from host and from argocd-server" {
  local host_iss pod_iss
  host_iss=$(curl -s "${ISSUER}/.well-known/openid-configuration" | jq -r .issuer 2>/dev/null || true)
  pod_iss=$(kubectl --context k3d-hub-cluster -n argocd exec deploy/argo-cd-argocd-server -- bash -c \
    'exec 3<>/dev/tcp/keycloak.localhost/80; printf "GET /realms/lab/.well-known/openid-configuration HTTP/1.0\r\nHost: keycloak.localhost\r\n\r\n" >&3; cat <&3' 2>/dev/null \
    | grep -o '"issuer":"[^"]*"' | cut -d'"' -f4 || true)

  [ "$host_iss" = "$ISSUER" ]
  [ "$pod_iss" = "$ISSUER" ]
}

@test "Gate 10b: Argo CD advertises Keycloak SSO (PKCE)" {
  local settings
  settings=$(curl -s http://localhost/api/v1/settings)
  [ "$(jq -r '.oidcConfig.issuer // ""' <<<"$settings")" = "$ISSUER" ]
  [ "$(jq -r '.oidcConfig.enablePKCEAuthentication // false' <<<"$settings")" = "true" ]
}

@test "Gate 10c: SSO entry points reach Keycloak login form" {
  for start in "http://localhost/auth/login?return_url=http%3A%2F%2Flocalhost%2Fapplications" \
               "http://argocd.localhost/auth/login?return_url=http%3A%2F%2Fargocd.localhost%2Fapplications" \
               "http://headlamp.localhost/"; do
    local kc_url
    kc_url=$(curl -s -o /dev/null -w '%{redirect_url}' "$start")
    [[ "$kc_url" == "${ISSUER}/protocol/openid-connect/auth?"* ]]
    run curl -s "$kc_url"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "id=\"kc-form-login\"" ]]
  done
}

@test "Gate 10d: Local platform-admin break-glass login succeeds" {
  local pw_file="${SECRET_DIR}/argocd-platform-admin.password"
  local token
  token=$(jq -n --rawfile p "$pw_file" '{username: "platform-admin", password: ($p | rtrimstr("\n"))}' \
    | curl -s -H 'Content-Type: application/json' -d @- http://localhost/api/v1/session | jq -r '.token // ""')
  [ -n "$token" ]
}

@test "Gate 10e: Headlamp requires SSO and refuses cross-origin access" {
  local hl
  hl=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Origin: https://evil.example' http://headlamp.localhost/clusters/k3d-spoke-prod/api/v1/namespaces)
  [[ "$hl" == "302 ${ISSUER}/protocol/openid-connect/auth?"*"client_id=headlamp"* ]]

  local cors
  cors=$(curl -s -D - -o /dev/null -H 'Origin: https://evil.example' http://headlamp.localhost/ | grep -i '^access-control-allow-origin' || true)
  [ -z "$cors" ]
}
