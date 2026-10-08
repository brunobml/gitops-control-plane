# Policy Reporter

> **Status: Current (2026-10-08).** Policy Reporter shows Kyverno's PolicyReports, the results of
> evaluating existing resources against the policies, for both spokes in one UI on the hub.

## Open the UI

**http://policy-reporter.localhost**: *Sign in with Keycloak* (`platform-user` or `tenant-a-user`;
passwords: `make password`). The cluster selector at the top switches between `spoke-nonprod`
and `spoke-prod`. Policy results of the ImageValidatingPolicy `tenant-images-signed` are under
the source *KyvernoImageValidatingPolicy*.

## Policies

All policies live in `platform-catalog/blueprints/` and reach the spokes through `kro-blueprints-<spoke>`
(spoke-nonprod follows `main`, spoke-prod a pinned tag in `clusters/blueprint-revisions.env`).

| Policy | Mode | Category, severity |
|---|---|---|
| `tenant-images-signed` (ImageValidatingPolicy) | **Deny** | Supply Chain Security, high |
| `require-resource-limits` | Audit | Best Practices, medium |
| `require-health-probes` | Audit | Best Practices, medium |
| `require-image-digest` | Audit | Supply Chain Security, medium |
| `require-recommended-labels` | Audit | Best Practices, low |
| `restrict-service-types` | Audit | Network Security, medium |

The Audit policies (`audit-policies.yaml`, 2026-10-08) only report, with `failurePolicy: Ignore`, on both
spokes (spoke-nonprod `main`, spoke-prod tag `v1.11.0`). They cover **every namespace except** `kube-system`
(managed by k3s), `kyverno` (no self-policing), `kube-public` and `kube-node-lease`; new namespaces are
covered automatically. `tenant-images-signed` (Deny) stays tenant-only. Kyverno evaluates the Pods and the
Deployments, DaemonSets, StatefulSets, Jobs and CronJobs behind them, not ReplicaSets (old revisions would
report outdated templates). The UI has two boards: **Tenants** (orders-*) and **Platform** (ack-system, kro,
monitoring, platform-probes, policy-reporter, platform-network, admission-probes). The hub runs no Kyverno,
so its namespaces are not covered. Policy
Reporter's **Policy Dashboard** lists every policy by title, grouped by its `policies.kyverno.io/category`
annotation, with pass/fail counts and the severity badge. A new policy needs those annotations
(`title`, `category`, `severity`, `description`), otherwise it lands in category "Other".

**Enforcing an Audit policy:** when its row shows 0 failures on both spokes for a while, set
`validationActions: [Deny]` and `failurePolicy: Fail` in the catalog, verify on spoke-nonprod, then
promote prod: tag the catalog (`git tag -a v1.X.0`), set `spoke-prod=v1.X.0` in
`clusters/blueprint-revisions.env`, `make promote-blueprints`.

## How it is built

```
browser ── policy-reporter.localhost ──> hub: policy-reporter-ui (Keycloak OIDC, client policy-reporter)
                                              │  http://k3d-<spoke>-serverlb/pr-core, /pr-kyverno
                                              │  (shared Docker network, Traefik basic auth)
                                              v
                spoke-nonprod / spoke-prod: policy-reporter (core) + policy-reporter-kyverno-plugin
                                              ^  PolicyReports
                                   kyverno-reports-controller
```

| Piece | Where |
|---|---|
| Hub UI, Argo CD app `addon-policy-reporter` | `applicationsets/addon-policy-reporter.yaml`, `addons/policy-reporter/values-hub.yaml` (the chart's core service is scaled to 0 on the hub: no Kyverno there) |
| Spoke APIs, apps `addon-policy-reporter-spoke-nonprod` / `-prod` | `applicationsets/addons-spoke-policy-reporter.yaml`, `addons/policy-reporter/values-spoke.yaml`, `addons/policy-reporter/spoke/middlewares.yaml` |
| PolicyReport producer | Kyverno's reports controller, enabled in `applicationsets/addons-spoke-kyverno.yaml` (overrides the admission-only default of platform-catalog) |
| Keycloak client `policy-reporter` | `addons/keycloak/realm-lab.json`; callback `http://policy-reporter.localhost/callback`, checked by CI (`ci/check-sso-urls.py`) |
| Secrets (never in Git) | `scripts/setup-policy-reporter-secrets.sh` (run by `setup-hub-spoke.sh`): `policy-reporter-client.secret` and `policy-reporter-api.password` in `~/.config/gitops-lab`; hub Secrets `policy-reporter-oidc`, `policy-reporter-cluster-<spoke>`; spoke Secret `policy-reporter-api-htpasswd`. The client secret also goes into `keycloak-realm-secrets` (`scripts/setup-keycloak-secrets.sh`) |
| Metrics | each spoke's Prometheus agent scrapes `job="policy-reporter"` and sends it to the hub |

## Verify

```bash
make test        # Gate 11d (APIs on both spokes: 401 without credentials, the image policy listed with them; UI on the hub redirects to Keycloak), Gate 12g (metrics)
kubectl --context k3d-spoke-nonprod get policyreports.wgpolicyk8s.io -A
kubectl --context k3d-spoke-nonprod get clusterpolicyreports.wgpolicyk8s.io
kubectl --context k3d-hub-cluster -n policy-reporter get deploy,ingress
```

## Troubleshooting

| Symptom | Check |
|---|---|
| The UI shows no cluster or an API error | Hub Secrets `policy-reporter-cluster-<spoke>` exist (`kubectl -n policy-reporter get secrets`); the spoke route answers 401 without credentials: `curl -s -o /dev/null -w '%{http_code}' -H 'Host: k3d-spoke-nonprod-serverlb' http://127.0.0.1:8081/pr-core/v1/namespaces` |
| Keycloak says "Invalid redirect uri" | the client `policy-reporter` in the realm and `ui.openIDConnect.callbackUrl` disagree; `make ci` (stage sso-urls) |
| Keycloak login fails with "invalid client credentials" | the client secret was regenerated: re-run `scripts/setup-keycloak-secrets.sh` and `scripts/setup-policy-reporter-secrets.sh`, then restart Keycloak and the UI |
| UI loads but shows no results; its log says `failed to call core API: EOF` | the spoke core's REST API is off: the chart enables it only with a local UI, so `values-spoke.yaml` sets `rest.enabled: true` |
| API answers `[]` for `/v2/sources` although PolicyReports exist | a source filter drops them: `tenant-images-signed` evaluates Pods (autogen off), so `values-spoke.yaml` sets `uncontrolledOnly: false` |
| Every second request to a spoke route or tenant app returns 404 | the spoke load balancer kept stale node IPs after a restart: `docker exec k3d-<spoke>-serverlb nginx -s reload` (done by `make start`; Gate 9b detects it) |
| A fixed workload still shows old failures | reports of objects Kyverno no longer evaluates (e.g. ReplicaSets before autogen excluded them) are only dropped at the next background scan (about 1 h); deleting them is safe, Kyverno regenerates what still applies: `kubectl get policyreports -A -o json \| jq -r '.items[] \| select(.scope.kind=="ReplicaSet") \| "\(.metadata.namespace) \(.metadata.name)"'` then `kubectl -n <ns> delete policyreport <name>` |
| No results at all | `kyverno-reports-controller` running on the spoke; PolicyReports exist (commands above) |

PolicyReports describe the current state of existing resources; they are not a history of blocked
admissions. For denied requests, use the Grafana dashboard *Kyverno — Daily Operations*.
