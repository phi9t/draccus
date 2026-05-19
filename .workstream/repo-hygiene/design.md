# Workstream: Repo Hygiene

**Owner:** Codex
**Status:** Closed (2026-05-14) — Phases 0–4 DONE; 182 GB of generated state relocated to `~/.automata/draccus/repo-hygiene-20260514T062236Z/`; `rootfs/`, `state/`, `cache/`, `build/` are symlinks back into the relocated tree; `.gitignore` tightened so source remains visible while generated paths stay out.
**Target completion:** 2026-05-14
**Related docs:** AGENTS.md §Workstream protocol, AGENTS.md §Critical invariants, DESIGN.md §Repository and bundle root

## 1. Goal

Make the checkout usable for source review and future work by moving generated local artifacts out of the repository root and into `~/.automata/draccus`, then tightening ignore rules so those artifacts do not reappear in `git status`. The end state is a repo root that contains tracked source, intentional untracked project files, and symlinks or documented external state only where Draccus runtime tools require the path to exist.

## 2. Out of scope

- Changing active Spack environment behavior or pinned versions.
- Fixing the current `draccus-probe` GLIBC failure.
- Reverting or rewriting existing tracked source diffs.
- Running destructive cleanup on build/runtime state before it has been relocated.
- Committing work.

## 3. Prerequisites (Phase 0)

| Requirement | How to verify |
|---|---|
| Current working tree state captured | `git status --short` saved under `artifacts/` |
| Artifact destination exists | `mkdir -p "$HOME/.automata/draccus"` |
| Destination has enough space | `df -h "$HOME/.automata/draccus"` |
| Artifact inventory captured | `du -sh` and top-level `find` output saved under `artifacts/` |
| No source edits mixed into artifact moves | Only generated/local paths moved; tracked source diffs remain unchanged |

## 4. Phase decomposition

1. Phase 0 — Snapshot and classify current repo state.
2. Phase 1 — Move local artifact directories and files to `~/.automata/draccus`.
3. Phase 2 — Recreate repo-facing paths as symlinks only where runtime scripts expect them.
4. Phase 3 — Update `.gitignore` for local agent/home/cache artifacts and relocated generated state.
5. Phase 4 — Validate hygiene: status, static gate, and artifact manifest.

## 5. Key decisions an agent must record

1. **Artifact destination layout** — record the final subdirectory under `~/.automata/draccus`.
2. **Symlink policy** — decide which moved directories are symlinked back into the checkout versus left absent.
3. **Keep vs relocate list** — record each top-level untracked path as source, local config, cache/build output, or unknown.
4. **Validation limitation** — record any pre-existing validation failures that remain after hygiene work.

## 6. Critical invariants

From AGENTS.md:

- These packages must ALWAYS resolve from `/opt/draccus/view/base-ml`, never from a `.venv`: `torch`, `jax`, `jaxlib`, `numpy`, `scipy`, `triton`, and any `nvidia-*` pip package.
- Inside bwrap: paths must be under `/opt/draccus` or `/workspace`.
- Never hardcode physical host paths (e.g. `/data02/home/philip.yang/...`) inside bwrap scripts.
- `DRACCUS_BUNDLE` is resolved portably via `lib/draccus-env.sh`.
- `draccus-run` mounts Spack read-only; `draccus-build` mounts it read-write.
- Do not change pinned versions without explicit request.
- `cuda_arch=100` and `TORCH_CUDA_ARCH_LIST=10.0` must not change without sign-off.
- After editing ANY file in `bin/`, `lib/`, `scripts/`, `envs/`, or `mise.toml`, run `./scripts/validate-static.sh`.

This workstream may edit `.gitignore` and `.workstream/repo-hygiene/*`. It must not edit `bin/`, `lib/`, `scripts/`, `envs/`, or `mise.toml` unless the scope is explicitly expanded.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---:|---|
| Moving `rootfs/`, `state/`, `cache/`, or `build/` breaks scripts that expect repo-local paths | High | Symlink required runtime paths back to the moved locations unless user opts for pure external state |
| Moving hidden local agent directories loses useful configuration | Medium | Relocate, do not delete; record manifest and destination |
| `git status --ignored` traverses huge caches and emits symlink-loop warnings | High | Move caches first, then use targeted status commands |
| Existing tracked source diffs get confused with hygiene work | Medium | Snapshot diffs before moving; avoid editing source files |
| Static validation remains red due to pre-existing bwrap/GLIBC issue | High | Record as pre-existing limitation; do not claim functional repair |

## 8. Definition of Done (whole workstream)

- `~/.automata/draccus/<run-id>/` contains relocated local artifacts with a manifest.
- Repo root no longer contains large cache/build scratch directories as physical directories.
- Runtime-required paths are symlinked back or documented as intentionally absent.
- `.gitignore` covers local agent/home/cache artifacts that should not be tracked.
- `git status --short` is significantly reduced and no longer dominated by generated artifacts.
- `./scripts/validate-static.sh` has been rerun after `.gitignore` edits; any remaining failure is documented.
- `tracker.org` has all executed tasks marked `DONE`, with artifacts listed.

## 9. Handoff protocol

Follow AGENTS.md §Workstream protocol. Do not remove relocated artifacts during handoff. If a downstream agent needs to reclaim disk, it should inspect the manifest under `~/.automata/draccus/<run-id>/` and confirm the symlink policy first.

## 10. File map

```
.workstream/repo-hygiene/
├── design.md
├── tracker.org
└── artifacts/
    ├── p0-status-before.txt
    ├── p0-du-before.txt
    ├── p1-move-manifest.txt
    ├── p4-status-after.txt
    └── p4-validate-static.log
```
