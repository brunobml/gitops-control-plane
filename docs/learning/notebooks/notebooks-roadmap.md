# Learning notebooks: roadmap

> **Status: Proposal (2026-10-09).** Nothing here is scheduled yet. The order is decided after the
> Phase 4 pilot (`docs/learning/pilot-protocol.md`): its findings show where learners actually get
> lost, and that picks the first notebook.

## Where we are

[`lab-commands.ipynb`](lab-commands.ipynb) is a **command cookbook**. It shows the hard-to-type
commands one by one, and each is followed by *Why it matters*. It teaches individual tools well, but
not how the pieces connect. The notebooks below cover that gap.

## Principles (all notebooks)

- **Read-only.** Running every cell never changes the lab. The disruptive drills stay in the
  student guide (Drill 1 *Lose the Cloud*, Drill 4), so they don't exist in two versions.
- **One question per notebook.** The title is the question it answers, such as "what owns what?".
- **Based on the live lab.** Explanations come from real output and say why it matters, not what the
  columns are ([README](README.md), rules for new cells).
- **Tested.** Every notebook runs headless in `make notebook-check` (extend it to all notebooks), and
  outputs never reach Git (nbstripout).
- **Same setup.** Bash kernel from `make notebook-setup`, opened with `make notebook` (browser) or
  VS Code; a Python kernel only where a chart teaches
  better than a table.

## Candidates, in proposed order

| # | Notebook | Question it answers | What the learner takes away | Kernel and tools |
| --- | --- | --- | --- | --- |
| 1 | `trace-an-order` | What owns what, from a URL to a commit? | Follows `orders-dev` through every layer: URL → Traefik Ingress → Service → Pod; worker → SQS queue in Moto through ACK; metrics in Prometheus, logs in Loki; then upward: kro instance → Argo CD app → Git commit. | Bash; `kubectl tree` (installed) |
| 2 | `follow-a-commit` | What happened after I pushed? | Takes a real platform-catalog commit: which spoke picked it up (`main` vs the prod tag), when Argo CD synced it (`app history`), which objects changed (events, new ReplicaSet), and what prod is still waiting for (`git diff v1.16.0..main`). Makes the promotion model concrete. | Bash; git |
| 3 | `security-posture` | Who can do what, and what stops them? | RBAC (`kubectl who-can`, `kubectl access-matrix`, both installed): can a tenant ServiceAccount create a Queue in `orders-prod`? Pod Security level per namespace, NetworkPolicies, and each admission guardrail tested with `--dry-run=server`. | Bash; krew plugins |
| 4 | `promql-by-example` | How do I ask Prometheus the right question? | `rate` vs `increase`, `sum by`, `histogram_quantile`, absent data, on real lab metrics (Kyverno admission latency, queue depth, Argo CD syncs), each query next to its chart. | Python (pandas, matplotlib) |
| 5 | `test-history` | Which smoke gates are flaky or slow? | Reads runs from the bats-test-reporter API: failure rate per gate, slowest tests, duration trend. Shows what to do with test data, and uses the new reporter. | Python (pandas, matplotlib) |

**Deferred:** a policy-authoring notebook with the Kyverno CLI offline (`kyverno test`). The CLI is
not installed, and writing policies is advanced. Notebook 3 covers the basics with server dry-runs.

## Prerequisites

- **Notebooks 4 and 5:** add `ipykernel`, `pandas` and `matplotlib` to
  [`requirements.txt`](requirements.txt), and register a second kernel *Python (lab)* in
  `scripts/setup-notebook.sh`.
- **Notebook 4 (Prometheus from Python):** query through the Kubernetes API, with
  `kubectl port-forward` to the hub's `prometheus-server` (or `kubectl exec`, as `lab-commands`
  does), never through a new Ingress: the Prometheus and Loki APIs have no authentication.
- **Notebook 5:** bats-test-reporter accepted by its independent validation (its API is the
  notebook's data source).
- **All notebooks:** `make notebook-check` runs every `*.ipynb` in this directory, not just
  `lab-commands.ipynb`.
- **Portable setup:** if the toolbox container is adopted
  (`docs/roadmaps/2026-10-09-portable-lab-toolbox-plan.md`), `lab notebook` serves them in
  JupyterLab from the toolbox (Docker and a browser are enough). On the WSL2 host, `make notebook`
  does the same today.

## Definition of done (per notebook)

1. It answers its question end to end on a fresh `make setup` lab.
2. `make notebook-check` passes, and no cell changes the lab (verify with `make lab-snapshot` before
   and after).
3. Every *Why it matters* cell was checked against the live lab.
4. A pilot learner (or the owner) completed it without help; record the stumbles in the pilot
   results template.
