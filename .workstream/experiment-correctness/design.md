# Workstream: Experiment Correctness

**Owner:** unassigned
**Status:** Active - blocked on `runtime-provenance`.
**Target completion:** Unscheduled
**Related docs:** `docs/training-substrate-roadmap.md`, `.workstream/runtime-provenance/design.md`

## 1. Goal

Add higher-level experiment guarantees on top of recorded and provenance-rich runs: replay, resume metadata sidecars, checkpoint compatibility checks, data/artifact locking, and failure classification.

## 2. Out of scope

- Cluster scheduling, node placement, rendezvous, retries, or membership.
- Framework-specific checkpoint implementation beyond sidecar/adapters.
- Security-boundary claims for agents.
- Remote artifact store implementation unless explicitly added later.

## 3. Prerequisites (Phase 0)

| Requirement | How to verify |
|---|---|
| Provenance-rich run records exist | Runtime provenance acceptance sample |
| Schema versioning exists | Run metadata has schema version |
| Project config contract exists | `draccus.yaml` is documented |

## 4. Phase decomposition

1. Phase 0 - Preflight and correctness policy decisions.
2. Phase 1 - Replay contract.
3. Phase 2 - Checkpoint sidecar and resume compatibility.
4. Phase 3 - Data/artifact locking policy.
5. Phase 4 - Failure classification and acceptance.

## 5. Key decisions an agent must record

1. Replay strictness and allowed drift.
2. Checkpoint sidecar schema.
3. Resume override semantics.
4. Data/cache locking modes.
5. Failure classification taxonomy.

## 6. Critical invariants

- Draccus remains local-runtime focused and does not own cluster orchestration.
- Checkpoint/resume support starts as sidecar metadata and compatibility checks, not a universal framework checkpoint format.
- Data/cache locking must not silently mutate shared datasets or foundation state.
- Any edits under `bin/`, `lib/`, or `scripts/` require Gate 0.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Replay promises deterministic science it cannot guarantee | High | Define replay as contract reconstruction, not identical stochastic output. |
| Checkpoint support becomes framework-specific too soon | Medium | Start with sidecar schema and adapters. |
| Data locking conflicts with shared HF caches | Medium | Define explicit floating vs snapshot modes. |
| Failure classification gets brittle | Medium | Keep taxonomy coarse until benchmarked. |

## 8. Definition of Done (whole workstream)

- Replay command reconstructs a recorded run contract or explains why it cannot.
- Checkpoint sidecar schema records step, hashes, config identity, and framework-adapter metadata.
- Resume checks compatibility and requires explicit override for declared drift.
- Data/artifact locking modes are documented and validated.
- Failure classification is coarse, rule-based, and represented in run metadata.
- Gate 0 passes.

## 9. Handoff protocol

Use `AGENTS.md` workstream protocol. Start only after runtime provenance has landed stable metadata schemas.

## 10. File map

```text
.workstream/experiment-correctness/
├── design.md
├── tracker.org
└── artifacts/
```
