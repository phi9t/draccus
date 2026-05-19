# Workstream: uv Overlay

**Owner:** unassigned
**Status:** Active — empirical `uv sync --frozen` check (P3.1) + the only outstanding code gap across all workstreams: `scripts/validate-projects-all.sh` (Gate 10c, P4.3). Phases 0–2 merged in commit `242bf4b`; Phase 3 partial; `bin/draccus-uv` auto-venv + foundation-package guards added in commit `96c7ce8`.
**Target completion:** TBD
**Depends on:** `.workstream/spack-envs-bootstrap/` (foundation must exist for `--system-site-packages` to see torch/jax/numpy), `.workstream/uv-in-rootfs/` (rootfs `uv`, `shims/pip`, and the `bin/draccus-uv` → `lib/draccus-uv.sh` resolver-guard chain).
**Related docs:** `DESIGN.md` (§8 uv overlays), `AGENTS.md` (do-not-shadow invariant, two-layer Python model), [`../INDEX.md`](../INDEX.md)

---

## 1. Goal

Take a Draccus bundle from "Spack base-ml installed" to "multiple parallel uv projects under `projects/` with checked-in `uv.lock` files, validated end-to-end by Gate 10 (per-project overlay), Gate 10b (DO_NOT_SHADOW + heavy inference ABI), and Gate 10c (whole-tree project sweep)". Concretely:

- `bin/draccus-project-init <name>` creates `projects/<name>/` with a working `.venv` that inherits `torch`/`jax`/`numpy`/`scipy` from `/opt/draccus/view/base-ml`.
- `scripts/validate-project-overlay.sh <name>` runs `uv sync --frozen` and re-asserts foundation paths.
- `scripts/validate_uv_layering.sh` scans every `projects/*/uv.lock` for DO_NOT_SHADOW pins.
- `scripts/validate-projects-all.sh` (Gate 10c) sweeps every real project and is wired into `scripts/validate-all.sh`.
- `DESIGN.md` §8 expanded with subsections 8.1–8.5; `AGENTS.md` pointer updated.

## 2. Out of scope

- Building or installing the Spack base-ml view itself (that's `spack-envs-bootstrap`).
- Generic `uv` internals; we use whatever upstream `uv` ships inside `base-sys`.
- Inner-loop ergonomics like watch-mode dev servers or test runners.
- A CPU-only project flavor (mentioned in §7 as a known future shape).

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

Each phase has tasks in `tracker.org` with explicit DoD and the commands to run. Phases are sequential; tasks within a phase may be parallelizable when marked so.

## 5. Decisions an agent must record (not invent)

Recorded in `tracker.org` under `* Decisions`. The four entries today were backfilled from merged code (commit `242bf4b`) and are tagged `SIGN_OFF: executor-default` — get explicit user approval before changing any of them:

1. **Project root convention** — `projects/<name>/` at repo root; `.gitignore` carves out `!projects/_template/`.
2. **`.python-version` source** — live `python -V` inside `draccus-run` at init time; never a hardcoded literal.
3. **Cache strategy** — shared `/opt/draccus/cache/uv` with `--link-mode=copy` (option A). Option B (per-project) is the fallback if P4.1 stress test surfaces contention.
4. **Lockfile flow** — `uv lock` inside `draccus-run`; commit `projects/<name>/uv.lock`; automation runs `uv sync --frozen`. Regeneration after a `base-ml` shift is a manual `uv lock` inside `draccus-run` until a helper script proves needed.

## 6. Invariants honored

This workstream **cites** the core invariants; it does not redefine them. The authoritative sources are `AGENTS.md` (Critical invariants §1–§5) and `DESIGN.md` (§6 environment, §8 uv layering). Honored here:

- **Two-layer Python model** (`AGENTS.md` "Two-layer Python model"; `DESIGN.md` §8). Spack owns `torch`, `jax`, `jaxlib`, `numpy`, `scipy`, `triton`, CUDA stack; uv owns `transformers`, `datasets`, `accelerate`, `peft`, `trl`, `vllm`, `flash-attn`, etc. The `_template/pyproject.toml` MUST NOT list a DO_NOT_SHADOW package in `dependencies`.
- **DO_NOT_SHADOW tri-redundancy** (`AGENTS.md` "Do-not-shadow list"). The list lives in `scripts/validate_uv_layering.sh` and is mirrored in `AGENTS.md` + `scripts/uv_overrides.txt`. Gate 0 enforces three-way sync. `bin/draccus-project-init` reads the list from `validate_uv_layering.sh` at runtime — do not duplicate it in any new script.
- **Canonical venv creation** (`AGENTS.md` "Two-layer Python model"). Every project venv: `uv venv --python "$(which python)" --system-site-packages .venv`. Hardcoding a Python literal (`python3.12`) is a regression — read it live from inside the namespace.
- **`UV_EXTRA_OVERRIDES` + `scripts/uv_overrides.txt`** (`DESIGN.md` §8). The overrides file is bound at `/opt/draccus/uv_overrides.txt` by `bin/draccus-run`; the uv resolver reads it as constraints *before* lock generation, so `uv lock` fails fast instead of silently shadowing.
- **`/opt/draccus` + `/workspace` prefix contract** (`AGENTS.md` "Canonical prefix contract"; `DESIGN.md` §4.2). Project sources live at `projects/<name>/` on the host, surface as `/workspace/projects/<name>/` inside the namespace. Never hardcode a host path in any project tooling.
- **draccus-run RO vs draccus-build RW** (`AGENTS.md`; `DESIGN.md` §5). Project init and all per-project `uv` operations run under `draccus-run` (Spack RO); only Spack rebuilds touch `draccus-build`.
- **Validation gate sequence** (`AGENTS.md` "Validation gate sequence"; `DESIGN.md` §10). This workstream extends the gate ladder with Gate 10 (per-project overlay), Gate 10b (layering scan + heavy ABI), and Gate 10c (project sweep). No gate added by this workstream is allowed to skip silently when no projects exist — it must print an info line and exit 0.
- **Mandatory `validate-static.sh` after any edit** (`AGENTS.md` "Mandatory: Run after every edit"). Pre-commit enforces it.

## 7. Necessary complexity (engineer onboarding)

Things the code does that an engineer cannot recover from reading individual files alone. Each item is short on purpose — for a fuller treatment, follow the file pointer.

### 7.1 Why `projects/_template/` is the unit of reuse
A single template stamped by `bin/draccus-project-init` is the only way every new project gets identical layering guarantees: same `pyproject.toml` shape, same `.gitignore`, same `.python-version` resolution path, same `--system-site-packages` venv. Without the template, every new project drifts and the DO_NOT_SHADOW invariant becomes a per-project audit instead of a one-shot setup.

### 7.2 `bin/draccus-uv` vs project `.venv` — orthogonal, not interchangeable
`bin/draccus-uv` is a **global one-shot** wrapper for `uv` operations inside the namespace (it sets `UV_EXTRA_OVERRIDES`, `UV_CACHE_DIR`, and the right Python path). For mutating `uv pip install/sync/uninstall`, it auto-creates or reuses the current workspace `.venv` and targets `/workspace/.venv/bin/python` unless the caller supplies an explicit target (`--python`, `--system`, `--target`, or `--prefix`). The per-project `.venv` is still the persistent activated environment for that project. Inside an already-active project shell: `source .venv/bin/activate && uv pip install …`. From the host: `bin/draccus-uv pip install …` is the safe equivalent.

### 7.3 `UV_EXTRA_OVERRIDES` is a constraint, not a pin
`scripts/uv_overrides.txt` lists the DO_NOT_SHADOW set as resolver guidance (read via `UV_EXTRA_OVERRIDES`). `draccus-uv` is the hard guard for host-side mutation: it rejects direct foundation requirements, dry-runs the resolved `uv pip install/sync` plan, and refuses any plan that would add `torch`/`jax`/`numpy`/`scipy`/`triton`/`nvidia-*` from PyPI. Gate 10b remains the runtime provenance scanner.

### 7.4 Why `--system-site-packages` is safe here
The `/opt/draccus/view/base-ml/lib/python3.12/site-packages` directory is **read-only inside `draccus-run`** (the bundle binds Spack RO). Combined with the resolver constraint (§7.3) and the post-hoc Gate 10b scanner (`validate_uv_layering.sh`), there are three independent barriers to a project venv shadowing the foundation. `--system-site-packages` is safe *because* of these barriers, not in spite of them — if you ever remove one, the safety argument collapses.

### 7.5 `uv.lock` lifecycle
- **Location:** `projects/<name>/uv.lock`, **tracked** in git. (Spack lockfiles are gitignored because they are auto-derivable from `envs/*/spack.yaml` + pinned Spack SHA; uv lockfiles are tracked because they pin fast-moving package versions whose resolution cannot be reproduced from `pyproject.toml` alone.)
- **Create / update:** `uv lock` inside `draccus-run` whenever `pyproject.toml` changes or `base-ml` shifts (a torch ABI bump invalidates downstream transitives).
- **Consume:** `uv sync --frozen` in automation; never bare `uv sync` (which can silently re-resolve).
- **Merge conflicts:** re-run `uv lock` after merging the `pyproject.toml` halves; never hand-edit `uv.lock`.

### 7.6 GPU-vs-CPU project flavors (forward-looking, out of scope)
Today there is one `base-ml` view (GPU, `cuda_arch=100`). If a CPU-only flavor ever lands, project templates need a `flavor:` field and `draccus-project-init` needs to pick the right base view. Out of scope for this workstream; documented here so it does not surprise the next maintainer.

## 8. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| `uv sync --frozen` ignores `--system-site-packages` and re-installs torch | Medium | P3.1 empirical check; fall back to `uv pip sync` if confirmed; Gate 10b catches any escapee at runtime |
| `projects/_template/` accidentally re-ignored by root `.gitignore` | Medium | Gate 0 check: `git check-ignore -v projects/_template/pyproject.toml` must NOT match |
| Shared uv cache corruption under parallel sync | Low | P4.1 stress test; `--link-mode=copy` reduces (does not eliminate) risk; option B fallback documented |
| Python pin drift between `_template/.python-version` and base-ml view | Medium | `bin/draccus-project-init` reads live `python -V` at init time, not from a literal |
| Gate 10c slows full validation linearly with project count | Low | Revisit past ~10 projects; consider parallelising `validate-projects-all.sh` |
| Lockfile invalidation when `base-ml` shifts (torch/jax ABI bump) | Medium | Document regeneration step in `tracker.org` Lockfile flow decision; consider a `refresh-projects-lockfiles.sh` helper in a follow-up workstream |
| `uv` resolver drift across `uv` versions (e.g. minor-version output changes) | Low | `uv` ships inside `base-sys` and is therefore version-pinned with the Spack bundle; bumping it requires a base-sys rebuild |

## 9. Definition of Done (whole workstream)

- All tasks in `tracker.org` marked `DONE` (or `WONTFIX` with rationale).
- `tracker.org` `* Decisions` section complete; every entry has a `SIGN_OFF` line; executor-defaults explicitly user-confirmed.
- `§6 Invariants honored` and `§7 Necessary complexity` in this file are current with any deviations discovered during execution.
- `scripts/validate-projects-all.sh` (Gate 10c) exists and is wired into `scripts/validate-all.sh`.
- `./scripts/validate-all.sh` exits 0 on a GPU host with ≥ 2 real projects present.
- `DESIGN.md` §§8.1–8.5 written and merged (P5.2 — touches user-owned core doc; needs sign-off).
- `AGENTS.md` updated with one-line pointer to `bin/draccus-project-init` and `DESIGN.md §8`.
- A short retrospective in `tracker.org * Retrospective` (≥ 3 bullets: surprises, automation candidates, doc gaps).

## 10. Handoff protocol for agents

When an agent picks up work:

1. Read this file end-to-end, then `tracker.org` top-to-bottom.
2. Pick the lowest-numbered `TODO` task whose `:DEPENDS:` are `DONE`.
3. Set status to `IN-PROGRESS`, fill in `:OWNER:` and `:STARTED:`.
4. Execute. Append non-trivial command output as `** Log` or in a `:LOGBOOK:` drawer; large logs go in `artifacts/` and stay untracked.
5. On completion: set to `DONE`, fill `:FINISHED:` (and `:COMMIT:` if applicable), record artifacts (paths, SHAs).
6. If blocked: set to `BLOCKED`, write the blocking condition under `** Blocker`, stop. Do not invent workarounds for the invariants in §6.

When handing back: leave the working tree clean (`git status` clean) or list intentional uncommitted state under `* Notes` in the tracker.

## 11. File map for this workstream

```
.workstream/uv-overlay/
├── design.md       this file
├── tracker.org     task tracker (org-mode)
└── artifacts/      created during execution: sync logs, uv.lock copies, validation timings
```
