# Workstream: Runtime Provenance

**Owner:** unassigned
**Status:** Active - blocked on `single-command-cli` recorded run directories.
**Target completion:** Unscheduled
**Related docs:** `docs/training-substrate-roadmap.md`, `.workstream/single-command-cli/design.md`

## 1. Goal

Extend operational run records into useful reproducibility records. A recorded run should capture enough metadata to understand which project, code state, bundle, selected environment, and foundation imports produced the execution.

## 2. Out of scope

- Checkpoint/resume compatibility.
- Dataset locking.
- Remote artifact stores.
- Scheduler or multi-node orchestration.

## 3. Prerequisites (Phase 0)

| Requirement | How to verify |
|---|---|
| Recorded run directories exist | `draccus run --name smoke -- true` produces a run dir |
| Project config schema exists | `draccus.yaml` is parsed by CLI |
| Gate 0 baseline known | `./scripts/validate-static.sh` |

## 4. Phase decomposition

1. Phase 0 - Preflight and schema decisions.
2. Phase 1 - Run metadata schema.
3. Phase 2 - Git/project snapshot.
4. Phase 3 - Foundation import provenance.
5. Phase 4 - Docs, tests, and acceptance.

## 5. Key decisions an agent must record

1. Which git dirty details are captured and how redaction works.
2. Which environment variables are captured by default.
3. Import provenance package set.
4. JSON schema versioning.

## 6. Critical invariants

- Do not capture secrets casually; provenance must have redaction and bounded size.
- Do not mutate project dependencies or foundation state during recording.
- Foundation package provenance must respect the do-not-shadow invariant.
- Any edits under `bin/`, `lib/`, or `scripts/` require Gate 0.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Dirty diff leaks secrets | Medium | Prefer status/hash summaries first; require explicit opt-in for patch capture. |
| Metadata capture slows launch | Medium | Keep default capture bounded and cheap. |
| Provenance format churn | Medium | Version schemas from first implementation. |

## 8. Definition of Done (whole workstream)

- Run records include schema-versioned metadata.
- Records capture project config snapshot, bundle identity, git commit/status, selected env vars, and foundation import provenance.
- Metadata has documented redaction and size limits.
- Gate 0 passes.

## 9. Handoff protocol

Use `AGENTS.md` workstream protocol. Start only after `single-command-cli` has stable run directory semantics.

## 10. File map

```text
.workstream/runtime-provenance/
├── design.md
├── tracker.org
└── artifacts/
```
