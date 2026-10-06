#!/usr/bin/env bats
# tests/smoke/06_observability.bats

setup() {
  load "common.bash"
}

@test "Gate 12a: Hub Prometheus receives scrape metrics from both spokes" {
  for spoke in spoke-nonprod spoke-prod; do
    local n
    n=$(promq "count(up{cluster=\"${spoke}\"} == 1)" | jq -r '.data.result[0].value[1] // 0')
    [ "$n" -ge 5 ]
  done
}

@test "Gate 12b: Synthetic HTTP blackbox probes are healthy" {
  local failed
  failed=$(promq 'probe_success{job="blackbox"} == 0' | jq -r '[.data.result[].metric.probe] | join(",")')
  [ -z "$failed" ]
}

@test "Gate 12c: Logs shipped from hub, spoke-nonprod and spoke-prod, and Loki is up" {
  for cl in hub spoke-nonprod spoke-prod; do
    local r
    r=$(promq "sum(rate(loki_write_sent_entries_total{cluster=\"${cl}\"}[10m]))" | jq -r '.data.result[0].value[1] // 0')
    local ok
    ok=$(awk -v r="$r" 'BEGIN{print (r > 0) ? 1 : 0}')
    [ "$ok" -eq 1 ]
  done
  local loki_up
  loki_up=$(promq 'up{job="loki"}' | jq -r '.data.result[0].value[1] // 0')
  [ "$loki_up" -eq 1 ]
}

@test "Gate 12d: Discovered TeamEKSCluster claims report ready in Prometheus" {
  local claims=()
  for spoke in spoke-nonprod spoke-prod; do
    local ctx="k3d-${spoke}"
    run kubectl --context "$ctx" get teamekscluster -A -o jsonpath='{range .items[*]}{"'${spoke}'|"}{.metadata.namespace}{"|"}{.metadata.name}{"\n"}{end}'
    [ "$status" -eq 0 ]
    while IFS='|' read -r cl ns name; do
      [[ -n "$name" ]] && claims+=("${cl}|${ns}|${name}")
    done <<< "$output"
  done

  # Require at least 2 claims discovered matching registered tenant-iac applications
  [ "${#claims[@]}" -ge 2 ]

  for claim in "${claims[@]}"; do
    local cl ns name t0 r=""
    IFS='|' read -r cl ns name <<< "$claim"
    t0=$(date +%s)
    until [ -n "$r" ]; do
      r=$(promq "lab_team_cluster_ready{cluster=\"${cl}\",namespace=\"${ns}\",name=\"${name}\"}" | jq -r '.data.result[0].value[1] // empty')
      [ -n "$r" ] && break
      if [ $(( $(date +%s) - t0 )) -gt 60 ]; then
        break
      fi
      sleep 2
    done
    [ -n "$r" ]
    [ "$r" = "1" ]
  done

  local team_unready
  team_unready=$(promq 'lab_team_cluster_ready == 0' | jq -r '[.data.result[] | "\(.metric.cluster)/\(.metric.namespace)/\(.metric.name)"] | join(",")')
  [ -z "$team_unready" ]
}

@test "Gate 12e: No alerts persistently firing over 20 minutes" {
  local alerts
  alerts=$(kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null)
  local old
  old=$(jq -r --argjson now "$(date +%s)" '[.data.alerts[] | select(.state=="firing" and ((.activeAt | sub("\\.[0-9]+";"") | fromdateiso8601) < ($now - 1200))) | .labels.alertname] | unique | join(",")' <<<"$alerts")
  if [[ -n "$old" ]]; then
    echo "Persistently firing alerts (>20m): ${old}" >&2
  fi
  [ -z "$old" ]
}

@test "Gate 12f: Grafana SSO entry point reaches Keycloak login form" {
  local kc
  kc=$(curl -s -o /dev/null -w '%{redirect_url}' http://grafana.localhost/login/generic_oauth)
  [[ "$kc" == "${ISSUER}/protocol/openid-connect/auth?"* ]]
  run curl -s "$kc"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "id=\"kc-form-login\"" ]]
}
