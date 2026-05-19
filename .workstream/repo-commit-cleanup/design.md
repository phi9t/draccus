# Workstream: Repo Commit Cleanup

**Owner:** Codex
**Status:** In progress
**Target completion:** 2026-05-19
**Related docs:** AGENTS.md §Workstream protocol, AGENTS.md §Git hygiene

## 1. Goal

Turn the current broad dirty tree into a clean repository state with intentional changes grouped into reviewable commits. The end state is `git status --short` clean, local-only artifacts ignored or relocated, and each commit covering one coherent concern.

## 2. Out of scope

- Reworking Draccus architecture beyond already-authored uncommitted changes.
- Changing pinned CUDA, torch, jax, Python, or `cuda_arch=100` values beyond the uncommitted work already present.
- Running GPU-heavy full acceptance unless required by the specific changed area.
- Deleting user work without either preserving it as an artifact or leaving it documented.

## 3. Prerequisites

| Requirement | How to verify |
|---|---|
| Dirty tree captured before cleanup | `git status --short` saved under `artifacts/` |
| Untracked paths classified | source/config, workstream evidence, local-only, or scratch |
| Mandatory static gate available | `./scripts/validate-static.sh` |
| Git identity available for commits | `git config user.name` and `git config user.email` |

## 4. Phase decomposition

1. Phase 0 — Snapshot and classify dirty tree.
2. Phase 1 — Tidy local-only artifacts and scratch.
3. Phase 2 — Run validation gates required by touched paths.
4. Phase 3 — Commit in coherent groups.
5. Phase 4 — Final status and handoff.

## 5. Key decisions an agent must record

1. **Commit grouping** — list the planned commit boundaries before committing.
2. **Local-only handling** — record any ignored or relocated files.
3. **Validation limitation** — record any gate that cannot be run or does not pass.

## 6. Critical invariants

- After editing any file in `bin/`, `lib/`, `scripts/`, `envs/`, or `mise.toml`, run `./scripts/validate-static.sh`.
- Do not change pinned versions or `cuda_arch=100` without explicit user approval.
- Do not commit generated `rootfs/`, `state/`, `cache/`, `build/`, project venvs, or local runtime artifacts.
- Preserve user work: do not revert unrelated changes; classify and commit or document intentionally uncommitted state.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---:|---|
| Untracked source is accidentally dropped | Medium | Use `git ls-files --others --exclude-standard` and classify before staging |
| Commits mix unrelated concerns | Medium | Stage by path group and inspect `git diff --cached --stat` before each commit |
| Static validation fails due to pre-existing runtime issue | Medium | Save log under `artifacts/` and record limitation in tracker |
| Local settings leak into git history | Medium | Ignore `.claude/settings.local.json`; commit only project-level config |

## 8. Definition of Done

- Dirty tree snapshot and final status are saved under `artifacts/`.
- Local-only files are ignored or documented.
- `./scripts/validate-static.sh` result is recorded.
- Commits are created with narrow, descriptive messages.
- `git status --short` is clean, or intentional uncommitted state is listed in `tracker.org * Notes`.

## 9. Handoff protocol

Follow AGENTS.md §Workstream protocol. This workstream is cleanup-only; do not use it as a place to continue feature implementation.

## 10. File map

```
.workstream/repo-commit-cleanup/
├── design.md
├── tracker.org
└── artifacts/
    ├── p0-status-before.txt
    ├── p0-untracked-before.txt
    ├── p2-validate-static.log
    └── p4-status-after.txt
```
