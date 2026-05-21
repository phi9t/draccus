# Workstream: Release Channels

**Owner:** unassigned
**Status:** Active - blocked on `bundle-packaging`.
**Target completion:** Unscheduled
**Related docs:** `docs/training-substrate-roadmap.md`, `.workstream/bundle-packaging/design.md`, `DESIGN.md`

## 1. Goal

Turn packaged B200 foundation bundles into inspectable releases with manifests, validation reports, compatibility contracts, and a reveal workflow. Named remote channels are a later extension, but the first schema should not block them.

## 2. Out of scope

- Multi-arch foundation builds beyond the existing B200 target.
- Changing pinned foundation versions.
- Scheduler integration.
- Automatic remote download/install.

## 3. Prerequisites (Phase 0)

| Requirement | How to verify |
|---|---|
| Bundle packaging landed | `draccus bundle pack` and `draccus bundle unpack` work |
| B200 validation host available | `nvidia-smi -L` and doctor pass |
| Gate outputs available | Run relevant validation scripts and save logs |

## 4. Phase decomposition

1. Phase 0 - Preflight and release evidence decisions.
2. Phase 1 - Foundation manifest schema.
3. Phase 2 - Validation report generation.
4. Phase 3 - Reveal/check workflow.
5. Phase 4 - Future channel design notes and acceptance.

## 5. Key decisions an agent must record

1. Release manifest required fields.
2. Validation gates required for a B200 release.
3. Compatibility contract fields.
4. Reveal command shape.

## 6. Critical invariants

- B200 target uses `cuda_arch=100` and `TORCH_CUDA_ARCH_LIST=10.0`; do not change without explicit sign-off.
- Pinned foundation versions remain unchanged unless the user explicitly requests a version change.
- Release evidence records the built bundle; it does not mutate the foundation.
- Any edits under `bin/`, `lib/`, `scripts/`, or `envs/` require Gate 0.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Release status implies more validation than was run | Medium | Reports must distinguish required, skipped, and unavailable gates. |
| Future named channel model conflicts with local bundles | Medium | Keep manifest identity independent from install location. |
| Validation logs are too large | Medium | Store summaries in manifest and raw logs as optional artifacts. |

## 8. Definition of Done (whole workstream)

- A packaged bundle can carry or reference a foundation manifest.
- Validation report captures gate status, B200 compatibility, driver floor, and caveats.
- Reveal workflow lets a research engineer independently inspect the selected foundation.
- Docs explain local releases and future channel path.
- Gate 0 passes.

## 9. Handoff protocol

Use `AGENTS.md` workstream protocol. Start only after bundle packaging has working archive and manifest behavior.

## 10. File map

```text
.workstream/release-channels/
├── design.md
├── tracker.org
└── artifacts/
```
