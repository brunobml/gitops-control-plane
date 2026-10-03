# Argo CD Visual Design, UI/UX Standards & Naming Best Practices

> **Status: Design reference.** Design rationale and target state. Examples and names may differ from what is deployed. For the running lab, see the [README](../README.md) and the [runbooks](runbooks/).

## Executive Summary

As a Kubernetes platform scales to dozens of development teams and hundreds of microservices, the **GitOps User Experience (DevEx)** becomes critical. When engineers, SREs, or on-call operators log into the Argo CD web dashboard, they need to answer three fundamental questions within seconds:
1. **What is this application?** (Domain & service identity)
2. **Where is it running and in what stage?** (Cluster target, namespace, and environment)
3. **How do I inspect its health, code, and live endpoints?** (Actionable deep links and metadata)

This guide documents the design rationale, naming conventions, and UI/UX configurations implemented in our enterprise GitOps control plane.

---

## 1. The Anti-Pattern: Generic Tenancy Naming

In early platform prototypes, applications are frequently given abstract identifiers such as `tenant-a-dev`, `tenant-b-test`, or `tenant-a-prod`.

```
❌ ANTI-PATTERN: Abstract Tenancy View
┌────────────────────────────────────────────────────────────────────────┐
│  📦 tenant-a-dev       [Healthy] [Synced]    Target: spoke-nonprod     │
│  📦 tenant-a-prod      [Healthy] [Synced]    Target: spoke-prod        │
│  📦 tenant-a-test      [Healthy] [Synced]    Target: spoke-nonprod     │
│  📦 tenant-b-dev       [Healthy] [Synced]    Target: spoke-nonprod     │
└────────────────────────────────────────────────────────────────────────┘
```

### Why This Fails at Scale:
* **Obscured Service Identity**: An on-call engineer during an incident has to guess which microservice `tenant-a` actually represents.
* **Broken Search & Filtering**: Typing `orders` or `billing` into the Argo CD search bar yields zero results.
* **Disjointed URLs & Namespaces**: Argo CD routes to `/applications/tenant-a-dev` and pods deploy into namespace `tenant-a-dev`, making `kubectl` debugging unintuitive.

---

## 2. The Solution: Convention 1 (`<app>-<env>`)

We adopt **Convention 1: `<app>-<env>`** as the standard application naming strategy across the platform:

```
✔ BEST PRACTICE: Domain-Driven View
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Argo CD UI - Applications Grid View                                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  📦 orders-dev        [Healthy] [Synced]    Labels: env=dev, team=e-commerce    │
│  Target: spoke-nonprod / ns: orders-dev                                         │
│  Links: [Live UI ↗] [GitHub ↗] [Helm Chart ↗] [AWS Moto ↗]                      │
│                                                                                 │
│  📦 orders-test       [Healthy] [Synced]    Labels: env=test, team=e-commerce   │
│  Target: spoke-nonprod / ns: orders-test                                        │
│  Links: [Live UI ↗] [GitHub ↗] [Helm Chart ↗] [AWS Moto ↗]                      │
│                                                                                 │
│  📦 orders-prod       [Healthy] [Synced]    Labels: env=prod, team=e-commerce   │
│  Target: spoke-prod    / ns: orders-prod                                        │
│  Links: [Live UI ↗] [GitHub ↗] [Helm Chart ↗] [AWS Moto ↗]                      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Key Advantages:
1. **Natural Alphabetical Sorting**: All lifecycle stages for a microservice (`orders-dev`, `orders-prod`, `orders-test`) sit side-by-side in the dashboard.
2. **Instant Search**: Typing `orders` immediately filters down to all stages of the orders microservice.
3. **Clean Kubernetes Parity**: Kubernetes namespaces mirror the application name (`orders-dev`, `orders-prod`), eliminating mapping confusion.
4. **Readable Deep Link URLs**: Directly browse to `http://localhost/applications/orders-dev`.

---

## 3. The 4 Pillars of a Meaningful Argo CD UI

To transform Argo CD from a raw status dashboard into an **operational platform portal**, we implement four UI pillars:

```mermaid
flowchart TD
    App["Argo CD Application Tile"]
    
    Pillar1["1. Filterable Sidebar Labels\n(team, environment, tier, framework)"]
    Pillar2["2. Clickable Header Deep Links\n(Live UI, GitHub repo, Helm OCI chart)"]
    Pillar3["3. Structured App Info Panel\n(Metadata key-value pairs)"]
    Pillar4["4. Resource Tree & Health Lua\n(Kro & ACK resource visualizations)"]
    
    App --> Pillar1
    App --> Pillar2
    App --> Pillar3
    App --> Pillar4
```

### Pillar 1: Filterable Metadata Labels
Labels attached to `metadata.labels` appear as clickable filter chips in the Argo CD sidebar.

```yaml
metadata:
  labels:
    app.kubernetes.io/name: "orders"
    app: "orders"
    environment: "dev"       # Enables filtering by stage (dev / test / prod)
    team: "e-commerce"      # Enables filtering by owning team squad
    tier: "backend"         # Enables filtering by architectural layer
    framework: "kro-ack"    # Identifies composition platform
```

* **User Impact**: A platform engineer supporting 50 squads can click `team: e-commerce` in the sidebar to filter out all unrelated applications instantly.

---

### Pillar 2: Actionable Deep Links with Font-Awesome Icons
Rather than requiring users to manually lookup ingress hosts, repository URLs, or cloud consoles, Argo CD renders clickable action links on each application card and resource node.

Configured in `clusters/values-argocd-hub.yaml` (`configs.cm.application.links`):

```yaml
configs:
  cm:
    application.links: |
      - title: "Live Orders Dashboard (Dev)"
        url: "http://orders-dev.localhost:8081"
        description: "Open Dev Orders Dashboard"
        icon.class: "fa-external-link"
        if: "app.metadata.name == \"orders-dev\""

      - title: "Orders GitHub Repository"
        url: "https://github.com/brunobml/orders-processor"
        description: "Open Application Source Code on GitHub"
        icon.class: "fa-github"
        if: "app.metadata.name startsWith \"orders-\""

      - title: "Platform Golden Chart"
        url: "https://github.com/brunobml/platform-charts"
        description: "Open Platform Engineering Golden Path Chart"
        icon.class: "fa-cubes"
        if: "app.metadata.name startsWith \"orders-\""

      - title: "Central Moto Cloud API"
        url: "http://localhost:5000/moto-api/"
        description: "Inspect Mock AWS Cloud State (SQS & DynamoDB)"
        icon.class: "fa-cloud"
        if: "app.spec.project == \"tenant-workloads\""
```

* **External Link Annotation**: Setting `link.argocd.argoproj.io/external-link` on the Application creates an external link button in the upper right header of the application view.

---

### Pillar 3: Structured Information Panel (`spec.info`)
When clicking into an application, the **Summary** drawer displays descriptive metadata key-value pairs:

```yaml
spec:
  info:
    - name: "Application"
      value: "Orders Processor"
    - name: "Environment"
      value: "{{ .env }}"
    - name: "Team"
      value: "E-Commerce Squad"
    - name: "Live Dashboard"
      value: "http://{{ .app }}-{{ .env }}.localhost:{{ .port }}"
    - name: "Source Code"
      value: "https://github.com/brunobml/orders-processor"
    - name: "Platform Golden Chart"
      value: "ghcr.io/brunobml/charts/queue-backed-service:1.0.0"
    - name: "Central Moto Cloud"
      value: "http://localhost:5000/moto-api/"
```

---

### Pillar 4: Custom Resource Health Visualizations (Lua Scripts)
By default, custom resources from Kro (`ResourceGraphDefinition`, `QueueBackedService`) and AWS ACK (`services.k8s.aws/*`) appear with `Unknown` health in Argo CD.

We inject custom Lua health scripts in `clusters/values-argocd-hub.yaml` under `resource.customizations`:
* **Kro Blueprints**: Evaluates `status.state == "Active"` and condition `Ready == True` to report **Healthy** or **Progressing**.
* **ACK Cloud Resources**: Inspects condition `ACK.ResourceSynced == True` to show green checkmarks on cloud queues and database tables.

---

## 4. Complete ApplicationSet Reference Specification

The live implementation is one ApplicationSet per tenant (Track B.2), e.g. [`applicationsets/tenant-workloads-tenant-a.yaml`](../applicationsets/tenant-workloads-tenant-a.yaml), generated by `scripts/tenant-appset.sh` from `scripts/templates/tenant-appset.yaml`. It is a single ApplicationSet (Phase 4 C.2) with goTemplate and `missingkey=error`. A **Git files generator** reads one registration file per app and environment, `tenant-workloads/tenants/<tenant>/apps/<app>-<env>.yaml`:

```yaml
tenant: tenant-a
app: orders
env: dev            # dev | test | prod -> spoke (nonprod / prod) and AWS account (111111111111 / 222222222222)
port: "8081"
valuesRevision: main   # prod: a full 40-character commit SHA
# valuesFile: deploy/values-orders-demo-dev.yaml   (optional; default deploy/values-<env>.yaml)
```

Abridged template, showing how the four pillars appear in it:

```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: https://github.com/brunobml/tenant-workloads.git
        files:
          - path: "tenants/*/apps/*.yaml"
  template:
    metadata:
      name: "{{ .app }}-{{ .env }}"                         # Convention 1 (the real template also validates env and the prod SHA)
      labels:                                               # Pillar 1
        app.kubernetes.io/name: "{{ .app }}"
        environment: "{{ .env }}"
        team: "e-commerce"
      annotations:                                          # Pillar 2
        link.argocd.argoproj.io/external-link: "http://{{ .app }}-{{ .env }}.localhost:{{ .port }}"
        link.argocd.argoproj.io/source-code: "https://github.com/brunobml/orders-processor"
        link.argocd.argoproj.io/platform-chart: "https://github.com/brunobml/platform-charts"
    spec:
      project: tenant-workloads
      info:                                                 # Pillar 3
        - name: "Platform Golden Chart"
          value: "ghcr.io/brunobml/charts/queue-backed-service:1.0.0"
      sources:
        - chart: queue-backed-service
          repoURL: ghcr.io/brunobml/charts
          targetRevision: 1.0.0
          helm:
            valueFiles:
              - '$values/{{ dig "valuesFile" (printf "deploy/values-%s.yaml" .env) . }}'
        - repoURL: https://github.com/brunobml/orders-processor.git
          targetRevision: "{{ .valuesRevision }}"
          ref: values
      destination:
        name: '{{ if eq .env "prod" }}spoke-prod{{ else }}spoke-nonprod{{ end }}'
        namespace: "{{ .app }}-{{ .env }}"
```

---

## 5. Summary Checklist for New Microservices

The ApplicationSet template already applies the naming, labels, links and info panel. A new microservice needs:
- [ ] An app name matching `orders-*` or `tenant-*` (AppProject `tenant-workloads` destinations), giving Application and namespace `<app>-<env>`.
- [ ] One registration file per environment in `tenant-workloads/tenants/<tenant>/apps/<app>-<env>.yaml`, using exactly the fields shown above.
- [ ] A values file per environment in the app repository (`deploy/values-<env>.yaml`, or the registration's `valuesFile`).
- [ ] An image from `ghcr.io/brunobml/` (allowlist VAP). `orders-processor` images must also carry its CI signature (Kyverno `tenant-images-signed`).
- [ ] For prod, a full commit SHA in `valuesRevision`, changed through a reviewed commit.
- [ ] `make post-bootstrap` once after the first sync, to provision the worker's cloud credentials.
