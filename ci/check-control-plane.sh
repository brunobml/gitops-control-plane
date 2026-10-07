#!/usr/bin/env bash
# CI for gitops-control-plane (2026-10-03 Track A.1). Locally: `make ci`. In GitHub: .github/workflows/ci.yaml.
#
#   shell        bash -n + shellcheck (warning level) on every tracked *.sh
#   secrets      credential patterns in tracked files (ci/secret-scan.py)
#   fixtures     ci/clusters.yaml labels still set by scripts/register-spokes.sh
#   render       every Application and ApplicationSet rendered offline (labci appsets: generators,
#                goTemplate, missingkey=error), then every source rendered (helm/kustomize/directory)
#                with this commit for gitops-control-plane and the promoted revisions of the other repos
#   schemas      kubeconform on everything rendered (CRD schemas from ci/schemas/)
#   alert-rules  promtool check + unit tests on the rendered hub alert rules
#   dashboards   Grafana dashboard JSON (valid, unique uid/title, referenced by the kustomization)
#   alloy        hub Alloy config parses
#   tenant-appsets tenant-workloads-<tenant>.yaml files equal scripts/tenant-appset.sh output (B.2)
#   iac-appsets tenant-iac-<team>.yaml files equal scripts/tenant-iac-appset.sh output
#   sso-urls     one OIDC issuer everywhere, every relying-party URL registered in the realm, no
#                old 8080/8443 hub URLs (Track I, review remark R-10; ci/check-sso-urls.py)
#   doc-markers  every bash block in the learner documents carries a valid doc-test marker
#                (learner on-ramp plan, Track C; tests/doc_tests.py --markers-only; no lab needed)
#   sandbox-guards  Lab 1 sandbox-down and the test-lab1 queue check fail closed on read errors
#                (tests/test-sandbox-guards.sh, stubbed docker/k3d/kubectl/aws; no lab needed)
#
# usage: ci/check-control-plane.sh [stage...]     (no stage = all)
CI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ci/lib.sh
source "$CI_LIB" "$@"
REPO=$(cd "${CI_DIR}/.." && pwd)
OUT="${LAB_CI_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"

if stage shell "Shell scripts (bash -n, shellcheck)"; then
  mapfile -t sh < <(git -C "$REPO" ls-files '*.sh')
  for f in "${sh[@]}"; do bash -n "$REPO/$f" || fail "bash -n: $f"; done
  if docker run --rm -v "$REPO:/mnt:ro" -w /mnt "${SHELLCHECK_IMAGE}" -S warning -x "${sh[@]}"; then
    ok "${#sh[@]} scripts: syntax and shellcheck clean"
  else
    fail "shellcheck findings"
  fi
fi

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$REPO" || fail "secret scan"
fi

if stage fixtures "Cluster generator fixtures match register-spokes.sh"; then
  missing=$(python3 - "$CI_DIR/clusters.yaml" "$REPO/scripts/register-spokes.sh" <<'EOF'
import sys, yaml
reg = open(sys.argv[2]).read()
for c in yaml.safe_load(open(sys.argv[1])):
    for k, v in c["labels"].items():
        if k == "environment":
            continue
        if f"{k}: {v}" not in reg and f'{k}: "{v}"' not in reg:
            print(f"{c['name']}: label {k}={v}")
EOF
  )
  if [[ -z "$missing" ]]; then ok "fixture labels are set by register-spokes.sh"; else fail "fixture labels not in register-spokes.sh: ${missing}"; fi
fi

if stage render "Render all Applications offline"; then
  tw=$(clone tenant-workloads main)
  ti=$(clone tenant-iac main)
  if labci appsets -clusters "${CI_DIR}/clusters.yaml" -revisions "$REPO/clusters/blueprint-revisions.env" \
       -repo "${GH}/tenant-workloads.git=${tw}" \
       -repo "${GH}/tenant-iac.git=${ti}" \
       "$REPO"/applicationsets/*.yaml "$REPO/bootstrap/root-app.yaml" > "$OUT/apps.yaml" \
     && python3 "${CI_DIR}/render.py" "$OUT/apps.yaml" --out "$OUT/manifests" \
       --repo "${GH}/gitops-control-plane.git=${REPO}" --repo "${GH}/tenant-iac.git=${ti}"; then
    ok "rendered $(ls "$OUT/manifests" | wc -l) Applications into $OUT/manifests"
  else
    fail "render"
  fi
fi

if stage schemas "Schema validation (kubeconform)"; then
  if [[ -d "$OUT/manifests" ]] && kubeconform "$OUT/manifests"; then ok "manifests valid"; else fail "kubeconform (run the render stage first)"; fi
fi

if stage alert-rules "Alert rules (promtool)"; then
  d=$(mktemp -d); chmod 755 "$d"
  if [[ -f "$OUT/manifests/addon-prometheus.yaml" ]]; then
    python3 - "$OUT/manifests/addon-prometheus.yaml" > "$d/alerting_rules.yml" <<'EOF'
import re, sys, yaml
for doc in yaml.safe_load_all(re.sub(r"[ \t]+$", "", open(sys.argv[1]).read(), flags=re.M)):
    if doc and doc["kind"] == "ConfigMap" and doc["metadata"]["name"] == "prometheus-server":
        print(doc["data"]["alerting_rules.yml"])
EOF
    cp "$REPO/addons/observability/alert-rules.test.yaml" "$d/"; chmod 644 "$d"/*
    if docker run --rm --entrypoint promtool -v "$d:/t:ro" -w /t "${PROMETHEUS_IMAGE}" check rules alerting_rules.yml \
       && docker run --rm --entrypoint promtool -v "$d:/t:ro" -w /t "${PROMETHEUS_IMAGE}" test rules alert-rules.test.yaml; then
      ok "alert rules valid and unit tests pass"
    else
      fail "promtool"
    fi
  else
    fail "alert-rules needs the render stage (addon-prometheus)"
  fi
  rm -rf "$d"
fi

if stage dashboards "Grafana dashboards"; then
  if python3 - "$REPO/addons/observability/dashboards" <<'EOF'
import json, os, sys, yaml
d = sys.argv[1]
listed = set(yaml.safe_load(open(os.path.join(d, "kustomization.yaml")))["configMapGenerator"][0]["files"])
uids, titles, errs = set(), set(), []
for f in sorted(x for x in os.listdir(d) if x.endswith(".json")):
    try:
        j = json.load(open(os.path.join(d, f)))
    except ValueError as e:
        errs.append(f"{f}: invalid JSON: {e}"); continue
    for k, seen in (("uid", uids), ("title", titles)):
        if not j.get(k): errs.append(f"{f}: no {k}")
        elif j[k] in seen: errs.append(f"{f}: duplicate {k} {j[k]}")
        seen.add(j.get(k))
    if f not in listed: errs.append(f"{f}: not in kustomization.yaml")
for f in listed - {x for x in os.listdir(d)}:
    errs.append(f"{f}: listed in kustomization.yaml but missing")
for e in errs: print("✘", e, file=sys.stderr)
print(f"✔ {len(uids)} dashboards checked", file=sys.stderr)
sys.exit(1 if errs else 0)
EOF
  then ok "dashboards valid"; else fail "dashboards"; fi
fi

if stage tenant-appsets "Tenant ApplicationSets match scripts/tenant-appset.sh (Track B.2)"; then
  python3 "${CI_DIR}/check-tenant-appsets.py" "$REPO" || fail "tenant ApplicationSets"
fi

if stage iac-appsets "Team ApplicationSets match scripts/tenant-iac-appset.sh"; then
  python3 "${CI_DIR}/check-tenant-iac-appsets.py" "$REPO" || fail "team ApplicationSets"
fi

if stage sso-urls "SSO URL consistency (Keycloak, Argo CD, oauth2-proxy, Grafana)"; then
  python3 "${CI_DIR}/check-sso-urls.py" "$REPO" || fail "SSO URLs"
fi

if stage doc-markers "Doc-test markers on every learner bash block (Track C)"; then
  python3 "$REPO/tests/doc_tests.py" --markers-only || fail "doc-test markers"
fi

if stage sandbox-guards "Lab 1 sandbox guards fail closed (validation-04 V3-1, V3-2; validation-05 V3-4)"; then
  bash "$REPO/tests/test-sandbox-guards.sh" || fail "sandbox guards"
fi

if stage alloy "Alloy configuration"; then
  alloy_syntax "$REPO/addons/observability/values-alloy-hub.yaml"
fi

finish
