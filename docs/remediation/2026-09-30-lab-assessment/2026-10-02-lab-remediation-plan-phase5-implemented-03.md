# Phase 5 Implementation Report — Run #03: Track C (Kyverno resilience) (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | Phase 5 v1.0 (GREEN LIGHT; remarks **R-2**, **R-4**) |
| **Executed by** | Claude (Opus 5.5). **To be validated by** Antigravity |
| **Commits** | `platform-catalog`: `8816e9d` (nonprod via `main`), tag **`v1.5.0`** (prod); `gitops-control-plane`: `832181b` |

## Outcome
| Step | Result |
|---|:-:|
| **C.1a spike** (R-4), nonprod, 2 replicas on separate nodes (default anti-affinity) | ✅ |
| **C.1** `admissionController.replicas: 2` + PDB `minAvailable: 1` (R-2), nonprod then prod | ✅ |
| **C.2** residual: scaling **both** replicas to 0 still removes the webhooks (Kyverno design) → now alerted by `KyvernoDown` (X8 fired in ~3 min) | ✅ monitored residual |

## Evidence
| Check | Result |
|---|---|
| R-2 capacity | spoke nodes < 10 % CPU/memory requested before the change |
| X11 / C.1a | background loop (signed pod admitted? unsigned pod denied? `ivpol` webhook present?) during a **rolling restart** and a **graceful delete of one replica**: 18 iterations over 170 s, **0 failures**, webhook present in every iteration |
| Prod | catalog v1.5.0: 2/2 ready, PDB `minAvailable 1`, unsigned denied / signed admitted (smoke stage 11) |
