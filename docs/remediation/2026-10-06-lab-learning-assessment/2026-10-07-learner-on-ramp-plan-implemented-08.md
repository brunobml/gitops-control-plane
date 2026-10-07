# Learner On-Ramp Plan: Implementation Report 08 (Lab 1: every command copy-and-paste, with why)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Owner request: "make sure all commands for the lab are there for me to copy and paste, and why I need to execute them". This follows the owner's walkthrough (implemented-07). Phase 3 is not accepted by this report.

## What changed
| Before | After |
|---|---|
| YAML shown as `yaml` blocks to save in an editor; step 2–5 edits described in prose ("change the volume", "add a constraint") | **every** action is a bash block: files are written with `cat > file <<'EOF'` (or appended with `>>`), and edits are exact `sed -i` commands followed by a `grep` that shows the changed line (no output means the edit did not apply) |
| "repeat for about a minute", `-w` watches that need Ctrl-C | `kubectl wait` (`--for=create`, `--for=delete`, `--for=condition=X=false`, `--for=jsonpath=…`), which returns as soon as the state is reached; `kubectl` 1.31+ is now listed as a prerequisite |
| no reason given for most commands | a **Why** paragraph before each of the 29 blocks |
| step 4 as two fragments | step 4 writes the complete blueprint once (steps 1–3 unchanged, plus the two lines marked `step 4`) and `diff`s it against the reference solution |
| `make test-lab1` played the **solution files** with its own commands; the doc's commands were never run (which is why the walkthrough found missing steps) | `make test-lab1` extracts the doc's 29 blocks (`id="…"` in the marker) and runs them **verbatim**, in order, in a temporary `~/lab1-work`. After each block it asserts what the doc promises: output text, kube state, an expected failure (`s5b-policy` must fail with the policy message), and fail-closed queue and children checks. It also checks that **every** doc block was run, in the doc's order |

The reference solution's `rgd.yaml` is now byte-identical to the file step 4 writes (generated from it); `rgd-with-queue.yaml` is regenerated from it.

## Evidence
| Test | Result |
|---|---|
| `make test-lab1` ×2 | rc 0, **60 checks**, 218 s and 210 s; "all 29 doc blocks run, in the doc's order" |
| `doc_tests.py --markers-only` | 86 bash blocks in 8 documents, 0 unmarked |
| `make ci` | all checks passed |

## For the validator and the owner
The owner's walkthrough can now be pure copy-and-paste: paste each block into one terminal, in order, and compare with **Measured**. Please keep `~/lab1-work` until the end (W-8, the empty page, is still open), and note the time per step.
