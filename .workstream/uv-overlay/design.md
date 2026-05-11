# Workstream: uv Overlay

**Owner:** unassigned
**Status:** Phase 0 — scaffolding committed; not yet started.
**Target completion:** TBD
**Related docs:** `DESIGN.md` (§8 uv overlays), `AGENTS.md` (do-not-shadow invariant, two-layer Python model)

---

## 1. Goal

Take a Draccus bundle from "Spack base-ml installed" to "multiple parallel uv projects under `projects/` with checked-in `uv.lock` files, validated by Gates 10 and 10c". Concretely:

- `bin/draccus-project-init <name>` creates `projects/<name>/` with a working `.venv` that inherits `torch`/`jax`/`numpy`/`scipy` from `/opt/draccus/view/base-ml`.
- `scripts/validate-project-overlay.sh` additionally runs `uv sync --frozen` and re-asserts foundation paths.
- `scripts/validate_uv_layering.sh` scans every `projects/*/uv.lock` for DO_NOT_SHADOW pins.
- `DESIGN.md` §8 expanded with subsections 8.1–8.5; `AGENTS.md` updated.

## 2. Out of scope

- Building or installing the Spack base-ml view itself (that's `spack-envs-bootstrap`).
- Generic uv internals; we use whatever upstream uv ships.
- Inner-loop ergonomics like watch-mode dev servers.

## 3. Prerequisites (Phase 0 — must hold before any agent starts)

| Requirement | How to verify |
|---|---|
| bwrap namespace working (Gate 1) | `./bin/draccus-probe` exits 0 |
| `/opt/draccus/view/base-ml` present with Python 3.12 (Gate 4) | `./bin/draccus-run state/view/base-ml/bin/python -V` |
| `uv` binary available inside `draccus-run` | `./bin/draccus-run which uv` |
| `./scripts/validate-static.sh` exits 0 (Gate 0) | `./scripts/validate-static.sh` |
| Pre-commit hooks installed | `pre-commit --version && ls .git/hooks/pre-commit` |

If any item fails: stop, document in `tracker.org`, escalate to owner.

## 4. Phase decomposition

```
Phase 0  Preflight & decisions
Phase 1  Project shape & template
Phase 2  bin/draccus-project-init
Phase 3  Lockfile + sync contract
Phase 4  Multi-project model + cache
Phase 5  Acceptance & retrospective
```

Each phase has tasks in `tracker.org` with explicit DoD (definition of done) and the commands to run. Phases are sequential; tasks within a phase may be parallelizable when marked so.

## 5. Key decisions an agent must record (not invent)

Before starting Phase 2, an agent MUST get sign-off (or read recorded decisions) on:

1. **Project root convention** — `projects/<name>/` at repo root; the `projects/` directory is in `.gitignore` by default; the `_template/` subtree is explicitly un-ignored. Record the un-ignore pattern in tracker.
2. **`.python-version` source** — read live from `python -V` output inside `draccus-run` at `bin/draccus-project-init` execution time; do NOT hardcode `3.12` as a literal in the script.
3. **Cache strategy** — shared `/opt/draccus/cache/uv` with `--link-mode=copy` (option A). Avoids per-project duplication; `copy` prevents cross-project hardlink corruption. Document option B (per-project) as the fallback if cache contention is observed.
4. **Lockfile flow** — `uv lock` inside `draccus-run`, commit `uv.lock`; consumers (CI, other agents) run `uv sync --frozen`. Do NOT allow `uv sync` without `--frozen` in automation.

These are recorded under `* Decisions` in `tracker.org`.

## 6. Critical invariants (do not break)

From `AGENTS.md` — verbatim, do not paraphrase:

- These packages must ALWAYS resolve from /opt/draccus/view/base-ml, never from a .venv: torch, jax, jaxlib, numpy, scipy, triton, and any nvidia-* pip package. The authoritative list lives in scripts/validate_uv_layering.sh DO_NOT_SHADOW array. To change it: get explicit user approval AND update both the array AND this file.
- Always create project venvs with: `uv venv --python $(which python) --system-site-packages .venv`
- Inside bwrap: paths must be under /opt/draccus or /workspace. Never hardcode physical host paths (e.g. /data02/home/philip.yang/...) inside bwrap scripts. DRACCUS_BUNDLE is resolved portably via lib/draccus-env.sh. draccus-run mounts Spack read-only; draccus-build mounts it read-write.
- After editing ANY file in bin/, lib/, scripts/, envs/, or mise.toml, you MUST run: `./scripts/validate-static.sh`. Do not propose a git commit until this passes.
- `bin/draccus-run` and `bin/draccus-build` set `PYTHONNOUSERSITE=1` and `UV_CACHE_DIR=/opt/draccus/cache/uv` — reuse, do not duplicate.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| `uv sync --frozen` ignores `--system-site-packages` and re-installs torch | Medium | Empirical Phase 3 check (P3.1); fall back to `uv pip sync` if confirmed |
| `projects/_template/` accidentally re-ignored by root `.gitignore` | Medium | Gate 0 check: `git check-ignore -v projects/_template/pyproject.toml` must NOT match |
| Shared uv cache corruption under parallel sync | Low | Stress-test in P4.1; `--link-mode=copy` reduces but does not eliminate risk |
| Python pin drift between `_template/.python-version` and base-ml view | Medium | `bin/draccus-project-init` reads live `python -V` at init time, not from static file |
| Gate 10c slows full validation linearly with project count | Low | Revisit past ~10 projects; consider parallelising `validate-projects-all.sh` |

## 8. Definition of Done (whole workstream)

- All tasks in `tracker.org` marked `DONE`.
- `./scripts/validate-all.sh` exits 0 on a GPU host with ≥2 real projects present.
- `DESIGN.md` §§8.1–8.5 written and merged.
- `AGENTS.md` updated with one-line pointer to `bin/draccus-project-init`.
- `tracker.org` `* Decisions` section is complete; `* Notes` captures any deviation from defaults.
- A short post-mortem note in tracker `* Retrospective` (≥ 3 bullets: what surprised us, what to automate next time, what to document).

## 9. Handoff protocol for agents

When an agent picks up work:

1. Read `tracker.org` top-to-bottom.
2. Pick the lowest-numbered `TODO` task whose dependencies are `DONE`.
3. Set status to `IN-PROGRESS`, fill in `:OWNER:` and `:STARTED:` properties.
4. Execute. Append all non-trivial command output (errors, timings, hash output) under the task's `:LOGBOOK:` drawer or a `** Log` subheading.
5. On completion: set to `DONE`, fill `:FINISHED:`, record artifacts (paths, SHAs).
6. If blocked: set to `BLOCKED`, write the blocking condition under `** Blocker`, and stop. Do not invent workarounds for the invariants in §6.

When handing back: leave the working tree clean (`git status` clean) or list intentional uncommitted state in tracker.

## 10. File map for this workstream

```
.workstream/uv-overlay/
├── design.md       this file
├── tracker.org     task tracker (org-mode)
└── artifacts/      created during execution: sync logs, uv.lock copies, validation timings
```
