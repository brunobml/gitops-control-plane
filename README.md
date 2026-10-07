# GitOps Control Plane (Hub Cluster)

This repository serves as the central GitOps control plane for a multi-cluster **Hub-and-Spoke** architecture using **Argo CD**, **Kro (K8s Resource Orchestrator)**, and **AWS Controllers for Kubernetes (ACK)** against a local centralized mock AWS cloud (**Moto**).

---

## 🏛 Architecture Overview

```mermaid
flowchart TD
    %% Subgraph boundary styling
    style Repos fill:#f8fafc,stroke:#94a3b8,stroke-width:1.5px,color:#0f172a
    style Hub fill:#eff6ff,stroke:#3b82f6,stroke-width:2px,color:#1e3a8a
    style Spokes fill:#f0fdf4,stroke:#22c55e,stroke-width:2px,color:#14532d
    style Cloud fill:#fffbeb,stroke:#f59e0b,stroke-width:2px,color:#78350f

    subgraph Repos["GitHub repositories (github.com/brunobml)"]
        GCP["gitops-control-plane<br/>(ApplicationSets, addons, projects)"]
        PC["platform-catalog<br/>(kro blueprints, admission policies, controllers)"]
        PCH["platform-charts<br/>(golden charts, OCI on GHCR)"]
        TW["tenant-workloads<br/>(application workload claims)"]
        TI["tenant-iac<br/>(team infrastructure claims)"]
        OP["orders-processor<br/>(app code, signed image, env values)"]
    end

    subgraph Hub["Hub cluster (k3d-hub-cluster), http://*.localhost"]
        Traefik["Traefik ingress"]
        ArgoCD["Argo CD (self-managed)<br/>localhost"]
        KC["Keycloak (SSO, realm lab)<br/>keycloak.localhost"]
        HL["Headlamp + oauth2-proxy<br/>headlamp.localhost"]
        Obs["Prometheus + Alertmanager, Loki,<br/>Grafana (grafana.localhost), blackbox, exporters"]
        AlloyH["Alloy (hub logs + events)"]
    end

    subgraph Spokes["Spokes: k3d-spoke-nonprod (orders-dev, orders-test) / k3d-spoke-prod (orders-prod)"]
        Kro["kro (QueueBackedService RGD)"]
        Ack["ACK SQS controller (CARM)"]
        Kyv["Kyverno (cosign signature check)<br/>+ native admission policies"]
        Agent["Prometheus agent + Alloy"]
        Orders["orders api + worker<br/>(per environment)"]
    end

    subgraph Cloud["Mock AWS (Docker)"]
        Moto["moto :5000<br/>SQS, accounts 111111111111 (nonprod) / 222222222222 (prod)"]
    end

    GCP --> ArgoCD
    PC --> ArgoCD
    TW --> ArgoCD
    PCH -->|Helm OCI| ArgoCD
    OP -->|values per env| ArgoCD
    ArgoCD -->|addons, blueprints, tenant apps| Spokes
    KC -.->|OIDC| ArgoCD
    KC -.->|OIDC| HL
    KC -.->|OIDC| Obs
    Traefik --> ArgoCD & HL & Obs & KC
    Kro --> Orders
    Kro --> Ack
    Ack -->|creates queues| Moto
    Orders -->|send / receive| Moto
    Agent -->|remote_write + log push, basic auth| Traefik
    AlloyH --> Obs

    %% Node color classes
    classDef repo fill:#f8fafc,stroke:#475569,stroke-width:1.5px,color:#0f172a;
    classDef hubItem fill:#e0f2fe,stroke:#0284c7,stroke-width:1.5px,color:#0369a1;
    classDef argo fill:#ffedd5,stroke:#f97316,stroke-width:2px,color:#9a3412;
    classDef spokeItem fill:#f0fdf4,stroke:#16a34a,stroke-width:1.5px,color:#14532d;
    classDef cloudItem fill:#fef3c7,stroke:#d97706,stroke-width:2px,color:#92400e;

    class GCP,PC,PCH,TW,OP repo;
    class Traefik,KC,HL,Obs,AlloyH hubItem;
    class ArgoCD argo;
    class Kro,Ack,Kyv,Agent,Orders spokeItem;
    class Moto cloudItem;
```

* **Argo CD on the hub** deploys everything, to itself and to both spokes. Changes reach the clusters only through Git.
* **Platform catalog:** prod follows a release tag, nonprod follows `main` (`clusters/blueprint-revisions.env`, then `make promote-blueprints`).
* **Tenant apps:** one file per app and environment in `tenant-workloads`. A prod change is a commit there that sets a full commit SHA.
* **Supply chain:** tenant images must come from `ghcr.io/brunobml/`, and the `orders-processor` images must be cosign-signed.

---

## 📂 Repository Structure

```
├── .github/CODEOWNERS                # Review owners for prod-relevant paths
├── addons/                           # Hub add-ons deployed by the addon-* ApplicationSets
│   ├── headlamp/                     # 🧭 Multi-cluster dashboard (values, kubeconfig secret script, README)
│   ├── keycloak/                     # 🔐 Keycloak SSO: realm "lab", ingress, NetworkPolicy, CoreDNS rewrite
│   ├── observability/                # 📈 Prometheus, Loki, Alloy, Grafana, blackbox values; alert rules + tests;
│   │                                 #    dashboards; credential-expiry exporter
│   └── probes/                       # Synthetic end-to-end order probe (runs on the spokes)
├── applicationsets/                  # Everything Argo CD deploys:
│                                     #   addon-*         hub add-ons (Traefik, Keycloak, Headlamp, oauth2-proxy, observability)
│                                     #   addons-spoke-*  spoke add-ons (kro, ACK SQS, Kyverno, agents, logging, platform config)
│                                     #   argo-cd         Argo CD manages itself (manual sync)
│                                     #   kro-blueprints  platform-catalog blueprints per spoke (revision from clusters/)
│                                     #   tenant-workloads-<tenant> one per tenant (scripts/tenant-appset.sh); one Application per registration file
│                                     #   platform-projects AppProjects
├── ci/                              # Track A CI toolkit: offline render, kubeconform, CEL, secret scan (`make ci*`)
├── bootstrap/                        # Root App-of-Apps and the hub deployer identity
├── clusters/
│   ├── blueprint-revisions.env       # Catalog revision per spoke (prod = release tag)
│   ├── platform-config/<spoke>/      # Per-spoke platform settings
│   └── values-argocd-hub.yaml        # Argo CD Helm values (OIDC, RBAC, health checks)
├── projects/                         # 🛡️ AppProject boundaries
├── docs/
│   ├── developer-tutorial.md         # Developer onboarding guide
│   ├── production-promotion-guardrails.md # Promotion patterns and guardrails
│   ├── argocd-visual-design-and-naming-standards.md # UI standards, labels, deep links, naming
│   ├── aws-well-architected-production-guide.md # Well-Architected review and production transition
│   ├── lab-progression-and-next-steps.md # Roadmap ideas
│   ├── ai-prompts/                   # Prompt for the AI-assisted lab assessment
│   ├── assessments/                  # Lab assessments (2026-09-30, 2026-10-03), one file per assessment
│   ├── runbooks/                     # Lifecycle, full rebuild, Argo CD CLI & SSO users, drills, student walkthrough
│   ├── roadmaps/                     # Phase 6: production parity on AWS EKS
│   └── remediation/
│       ├── 2026-09-30-lab-assessment/ # Plans, reports and validations for the 2026-09-30 assessment (Phases 1–5)
│       └── 2026-10-03-lab-assessment/ # Remediation of the 2026-10-03 assessment
├── scripts/
│   ├── setup-hub-spoke.sh            # Docker network, moto, 3 k3d clusters, Argo CD; registers the spokes
│   ├── register-spokes.sh            # Spoke tokens and Argo CD cluster secrets
│   ├── post-bootstrap.sh             # Mandatory after bootstrap and after every start (credentials, SSO, sync, smoke test)
│   ├── smoke-test-hub-spoke.sh       # End-to-end checks: runs the Bats suite in tests/smoke/
│   ├── promote-blueprints.sh         # Applies clusters/blueprint-revisions.env
│   ├── audit-impersonation.sh        # Checks that every Application syncs as its project's identity
│   ├── orphans.sh                    # Lists objects no Application owns
│   ├── setup-*-secrets.sh, setup-argocd-accounts.sh # Secrets generated into ~/.config/gitops-lab (never in Git)
│   ├── start-hub-spoke.sh / stop-hub-spoke.sh # Host reboot lifecycle
│   ├── push-all.sh                   # Pushes all 5 lab repos to GitHub
│   └── teardown-hub-spoke.sh         # Removes clusters, containers and network
├── Makefile                          # Developer workflow automation (`make help`)
└── README.md
```

---

## 🚀 Quick Start Guide

### 1. Provision Multi-Cluster Environment
Create the Docker network, the moto mock cloud, the three k3d clusters and Argo CD, and register the spokes:

<!-- doc-test: skip reason="creates the three clusters (part of the rebuild; see the full rebuild runbook)" -->
```bash
make setup
```

### 2. Push Repositories to GitHub
The lab reads six repositories under `https://github.com/brunobml`, checked out side by side:
- `gitops-control-plane`
- `platform-catalog`
- `platform-charts`
- `tenant-workloads`
- `tenant-iac`
- `orders-processor`

<!-- doc-test: skip reason="pushes all six repositories to GitHub" -->
```bash
# Push all six local lab repositories (use --dry-run to simulate)
make push
# or: bash scripts/push-all.sh --dry-run
```

### 3. Bootstrap the Control Plane
<!-- doc-test: skip reason="part of the rebuild; post-bootstrap also runs in every moto recovery" -->
```bash
make bootstrap        # AppProjects + root application; Argo CD deploys everything else from Git
make post-bootstrap   # Mandatory: worker cloud credentials, SSO prerequisites, Argo CD self-management,
                      # re-sync of anything stuck, then the smoke test
```

Without `make post-bootstrap` the lab is not complete:
* the workers have no SQS credentials;
* the `argo-cd` Application stays OutOfSync;
* the Bats smoke suite fails, at least *Gate 9* (orders end to end) and the *Gate 12* observability checks.

### 4. Verify & Test
<!-- doc-test: run timeout="900" expect="ok [0-9]+ Gate" -->
```bash
make test     # End-to-end smoke test: the Bats suite in tests/smoke/ (post-bootstrap already ran it once)
make status   # Applications, spoke controllers and moto queues
```

---

## 🎁 What you get

| What | Where | Sign in |
|---|---|---|
| **Argo CD** (desired state, all clusters) | http://localhost or http://argocd.localhost | "Log in via Keycloak", or the local break-glass `platform-admin` |
| **Headlamp** (runtime state, all clusters) | http://headlamp.localhost | Keycloak (via oauth2-proxy) |
| **Grafana** (metrics, logs, alerts) | http://grafana.localhost | Keycloak: `platform-user` = Admin, `tenant-a-user` = Viewer |
| **Keycloak admin** | http://keycloak.localhost/admin/ | `kc-admin` |
| **Orders dashboards** | `make open-dev` / `open-test` / `open-prod` (port-forward) | — |

**HTTPS:** `https://<host>.localhost` redirects to the HTTP URL above, which is the path SSO uses. For no certificate warning, do this once on Windows: `winget install FiloSottile.mkcert`, then `mkcert -install`. After that, run `make local-tls`. Without mkcert, the lab uses a self-signed certificate, and the browser warns once before redirecting.

**SSO users** (Keycloak realm `lab`):
* `platform-user`: platform administrator.
* `tenant-a-user`: tenant role in Argo CD, Viewer in Grafana.

`make password` prints where every password is stored. Passwords are generated into `~/.config/gitops-lab` (mode 600) and are never committed.

Argo CD from the command line (SSO and break-glass logins, RBAC checks, safe syncs), and a **temporary SSO user** for demos or pairing instead of sharing a password: [Argo CD CLI runbook](docs/runbooks/argocd-cli.md).

**Grafana dashboards:**
* *Platform overview*: Application health, spoke connections, firing alerts, scrape targets, recent warning events.
* *Logs & events*: Loki logs and Kubernetes events from all three clusters.

The 20 alert rules are unit-tested with `make test-alert-rules` (and in CI, `make ci`).

**Guardrails you can try:**
* Images from outside `ghcr.io/brunobml/` are denied in tenant namespaces.
* Unsigned `orders-processor` images are denied.
* QueueBackedService objects that break the contract are denied.
* Drift is reverted by Argo CD and ACK.

See the [operational drills](docs/runbooks/operational-drills-and-failure-injection.md).

**Learning the concepts** (not just the commands): start with the [student guide](docs/runbooks/devops-student-rebuild-guide.md) (objectives, checkpoints, *one change, four reconcilers*, the Drill 4 milestone), then the [developer tutorial](docs/developer-tutorial.md), and keep [Concepts, Glossary & Self-Check](docs/concepts-and-glossary.md) at hand.

---

## 🔄 Host Reboot & Lab Lifecycle

To pause or resume your local multi-cluster environment without losing state or re-provisioning:

<!-- doc-test: skip reason="stops and restarts the whole lab" -->
```bash
# Gracefully stop clusters and Moto before host shutdown/reboot
make stop

# Resume clusters and Moto after host reboot
make start
make post-bootstrap   # Mandatory after every start: moto restarts empty, so worker credentials are re-provisioned
```

For troubleshooting hanging Docker daemons, spoke connection errors, or token rotation, see the [Host Reboot & Lab Lifecycle Runbook](docs/runbooks/host-reboot-and-cluster-lifecycle.md).

---

## 🧹 Teardown

To completely clean up all clusters, mock cloud containers, and networks:

<!-- doc-test: skip reason="deletes the lab" -->
```bash
make teardown
```

To rebuild everything from Git and check the result (teardown → setup → bootstrap → post-bootstrap, about 8 minutes), follow the [Full Rebuild and Acceptance Runbook](docs/runbooks/full-rebuild-and-acceptance.md).

## AI-Assisted Lab Assessment

This repository includes a carefully crafted prompt that lets an AI agent (with live access to the cluster and repositories) perform a structured, multi-layered assessment of the lab as a Master DevSecOps Architect.

The agent evaluates architecture, GitOps maturity, security posture, production parity with a real EKS hub-spoke design, and how easy the lab is for new engineers to understand and extend.

→ See [`docs/ai-prompts/ai-agent-lab-assessment-prompt.md`](docs/ai-prompts/ai-agent-lab-assessment-prompt.md)
