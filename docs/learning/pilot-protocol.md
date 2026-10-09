# Learner Pilot: Facilitator Protocol (on-ramp Phase 4, Track D)

> **Status: Draft for owner approval (2026-10-07).** Prepared by Claude (Opus 5.5), the implementer of Lab 0 and Lab 1. The **facilitator** runs the sessions, and the **re-score** is done by someone other than Claude (plan guardrail G-5). Plan: [learner on-ramp §6](../remediation/2026-10-06-lab-learning-assessment/2026-10-07-learner-on-ramp-plan.md). **This file contains the answer key (§7): do not give it to learners.** Learners get the [briefing](pilot-learner-briefing.md) only.

## 1. Purpose
The learning assessment is at **8.0 / 10**, a score of the *teaching material*. It says explicitly that learner outcomes have not been measured. This pilot measures them: can someone new to the lab finish Lab 0 and Lab 1 alone, how long does it take, where do they get stuck, and what do they understand afterwards? No one may claim a score above 8.0 before this pilot (G-5).

## 2. Who
| Role | Who | Notes |
|---|---|---|
| Learners | **2–3 people new to the lab** (owner decision O-4). The owner may rehearse the labs, but is reported separately and does not count toward the new-learner sample | the agents (Claude, Codex, Antigravity) do **not** count |
| Facilitator | the owner | observes, times, records; does not teach |
| Re-scorer | Codex, Antigravity or the owner, **not Claude** | after the results are written |

Learner profile: knows `kubectl` basics (contexts, namespaces, `get`/`logs`/`describe`) and what a controller is, the same prerequisites as the [student guide](../runbooks/devops-student-rebuild-guide.md). Kro, ACK and this lab are new to them.

## 3. Where and how
* **Machine:** the owner's lab host (`OMEN30L`), in person or by screen share with remote control. The lab must already be running; learners never rebuild it.
* **Learner terminal:** a fresh terminal in `~`, logged in as the owner's Linux user only for learners the owner trusts with that account. This user can read every lab secret in `~/.config/gitops-lab` and other files available to the owner. Tell the learner to stay within the lab documents; use a separate Linux user if that access is inappropriate.
* **Two sessions per learner**, on the same day or on two days:
  * **A: Lab 0** ([guided tour](../lab-0-guided-tour.md)): stations 0–8. **Skip the optional Git step**: it pushes to a shared repository.
  * **B: Lab 1** ([write a blueprint](../lab-1-write-a-blueprint.md)): steps 0–6 including the stretch, the clean-up, and "Check yourself".
* **Think aloud:** ask the learner to say what they expect before each block and what surprised them afterwards. This is the main source of friction items.

## 4. Before each session (facilitator, about 5 min)

<!-- these commands are for the facilitator; the learner does not run them -->
```bash
cd ~/repos/gitops-control-plane && mkdir -p ~/pilot-records && chmod 700 ~/pilot-records
make test                                   # every line "ok", none "not ok"; otherwise fix first
make lab-snapshot > ~/pilot-records/P1-before.txt        # P1 = this learner's code
k3d cluster list                           # no learn-sandbox (session B starts without one)
rm -f ~/.config/argocd/lab0.config          # no Lab 0 CLI session left from an earlier learner
rm -rf ~/lab1-work                          # no Lab 1 files left from an earlier learner
```

* Have the [record template](pilot-record-template.md) ready as `~/pilot-records/P1-record.md`, **outside Git** (it contains free text about a person).
* Open only the lab document in the learner's browser or editor, not this protocol, the solution folder, or the remediation reports.
* Start a clock. Record the time **at the start of each station or step**, not afterwards.

## 5. During the session: rules for the facilitator
| Do | Do not |
|---|---|
| Stay silent unless asked, or until the learner has been stuck for **5 minutes** | Explain concepts, point at the answer, or say "almost" |
| Note every friction item **verbatim**: what they did, what they saw, what they said | Fix the documents during the session (note the item; fix afterwards) |
| When you must help, give the **smallest** hint and record it (`H1`, `H2`, …) | Count help with the terminal or the machine (a typo, a closed window) as a hint; record it as **logistics** instead |
| Let them answer the self-check questions **before** opening the folded answers, and write their answers in the record | Score during the session |

**What counts as a hint:** any information the documents should have given them: which command to run, what an output means, where a file is. **Logistics** are problems of the machine, not of the documents: a lost terminal, a typo they would have spotted themselves, the screen share.

## 6. After each session (facilitator, about 10 min)

Lab 0 station 6 deletes a cloud queue, and ACK recreates it within 300 s. Wait for that before taking the after-snapshot (`make test` checks the queues too).

<!-- these commands are for the facilitator -->
```bash
cd ~/repos/gitops-control-plane
make test                                                   # every line "ok"
make lab-snapshot > ~/pilot-records/P1-after.txt
diff ~/pilot-records/P1-before.txt ~/pilot-records/P1-after.txt && echo "lab unchanged"
k3d cluster list                                            # session B: no learn-sandbox left
rm -f ~/.config/argocd/lab0.config; rm -rf ~/lab1-work
```

If `diff` shows a difference, record it in the results. A changed lab is itself a finding (guardrail G-1). Then score the self-check answers with §7 and fill in the post-survey (§8) with the learner.

## 7. Self-check scoring (answer key; facilitator only)

The learner answers the **9 questions the labs ask** (Lab 0 station 8: 5 questions; Lab 1 "Check yourself": 4 questions), before opening the folded answers. An answer is **correct** when it contains the key point; wording does not matter. **Partial** counts as incorrect for the threshold but is recorded.

| # | Question (short) | Key point for "correct" |
|---|---|---|
| L0-1 | hand-scaled `orders-dev-worker` to 3: what one second later, why no Argo CD complaint? | back to **1**, because **kro** watches its children and restores them; Argo CD tracks only the `QueueBackedService`, which did not change |
| L0-2 | `list-queues` with the mock keys is empty: are the queues gone? | no: wrong **account** (mock keys = `123456789012`); the queues are in `111…`/`222…` (CARM) |
| L0-3 | `orders-dev-dlq` deleted in moto: who notices, when? | only **ACK**, at its next **resync** (≤ 300 s); Argo CD and kro see no Kubernetes change |
| L0-4 | why may `tenant-a-user` sync dev but not prod; what limits the app itself? | **RBAC** role `tenant-a` (sync only dev/test); the **AppProject** limits repositories and namespaces |
| L0-5 | where is an ACK Queue's health, and where not? | in the **tree view** (Lua health checks); **not** in `Application.status.resources` |
| L1-1 | why a ClusterRole per blueprint; risk of `unrestricted`? | **aggregation** limits kro to reviewed kinds; unrestricted kro would let any RGD author create anything, including RBAC (≈ cluster-admin) |
| L1-2 | instance has no status at all: first command? | the **kro log** (`forbidden`), then the RGD's conditions |
| L1-3 | B uses `${a.status.x}`: order, and if `x` never appears? | **A first**, B after `x` exists; if it never does, kro **waits** and B is never created |
| L1-4 | `replicas ≤ 5` on a blueprint with instances? | **not** a schema marker (kro refuses: breaking change, D-14); a **ValidatingAdmissionPolicy** |

## 8. Post-survey (5 questions, at the end of session B)
1. "I could do **Lab 0** without help." 1 (disagree) … 5 (agree)
2. "I could do **Lab 1** without help." 1 … 5
3. In one sentence: what does **kro** do that **Argo CD** does not? *(free text; a transfer check, not scored for the threshold)*
4. What was the most confusing moment, and where?
5. What would you change first?

## 9. Success thresholds (plan §6, as proposed there)
| Measure | Threshold |
|---|---|
| Lab 0 time | ≤ 75 min, **without hints** |
| Lab 1 time | ≤ 90 min, **≤ 1 hint** |
| Self-check | **≥ 7 / 9 correct** (plan: ≥ 6/8; see decision P-1) |
| Friction | every friction item is either fixed in the docs or answered in them, before the re-score |
| Lab state | `diff` of the before and after snapshots empty for every session |

## 10. Results and re-score
1. The facilitator writes `docs/learning/pilot-results-YYYY-MM-DD.md` from the [results template](pilot-results-template.md): anonymous (`P1`, `P2`, …), numbers and friction items only. The records in `~/pilot-records/` stay outside Git.
2. Friction items become fixes (implementer: Claude, validated by someone else, as for Phases 1–3).
3. **Independent re-score** of [the learning assessment](../assessments/2026-10-06-lab-learning-assessment.md) by Codex, Antigravity or the owner (not Claude), using [the assessment prompt](../ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md) plus the pilot results.

## 11. Decisions for the owner before the first session
| ID | Question | Recommendation |
|---|---|---|
| P-1 | Plan §6 says "the 8 self-check questions" (concepts page). Questions 6–8 there (state outside Git, admission layers, the simulated EKS) are **not taught** by Lab 0 or Lab 1. Score the 9 questions the labs ask instead? | **Yes**, threshold ≥ 7/9 (78 %, close to 6/8 = 75 %). Optionally add the concepts page's 8 as an *untaught* control, reported separately |
| P-2 | Sessions on the owner's machine, as the owner's Linux user? | **Yes** for the pilot (low friction; the secret-visibility risk is recorded in §3). A separate Linux user would need its own kubeconfig and Docker access |
| P-3 | Where do raw records live? | `~/pilot-records/`, **outside Git**; only the anonymous results file is committed |
