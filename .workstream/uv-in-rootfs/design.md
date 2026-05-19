# Workstream: uv in rootfs + pip blocked

**Owner:** Cursor agent session (2026-05-11)
**Status:** Closed (2026-05-11) — Phases 0–5 DONE; `uv` pinned at `rootfs/usr/local/bin/uv` (version + sha256 in `scripts/uv-version.env`); `shims/{pip,pip3}` shadow Spack's `py-pip` via PATH order; `bin/draccus-uv` delegates to `lib/draccus-uv.sh` (auto-venv + foundation-package guards landed in commit `96c7ce8`).
**Target completion:** TBD
**Related docs:** `DESIGN.md` (§4 path contract, §6 environment, §8 uv layering), `AGENTS.md` (critical invariants), `README.md` (thesis), commit `fefc6da` ("ML-first default PATH, draccus-uv as first-class, researcher-first docs").

---

## 1. Goal

Make the bundle's `uv` toolchain a pinned rootfs artifact and make `pip` structurally uncallable on the common paths. After this workstream:

- `uv` inside any `draccus-{run,shell,uv}` resolves to a pinned binary at `rootfs/usr/local/bin/uv` (single source of truth, no host dependency).
- `pip` and `pip3` on PATH inside the namespace resolve to bundle-shipped shims that exit non-zero with `use 'draccus-uv pip <args>' instead`. The Spack-shipped `pip` (from `py-pip` in `base-ml/view`) is shadowed by a shims directory prepended to PATH.
- Project venvs (created by `draccus-project-init` or any `draccus-uv venv` invocation) have `.venv/bin/pip*` replaced with the same shim — closes the `source .venv/bin/activate && pip install torch` shadow path.
- `bin/draccus-run` no longer mounts any host binary. The `DRACCUS_HOST_UV_BIN` knob is deleted. The `host_uv_*` block (lines 80–104 in current `bin/draccus-run`) is removed.
- `bin/draccus-uv` stays a thin entrypoint, with behavior delegated to `lib/draccus-uv.sh`.
- `draccus-uv pip install ...` auto-creates/uses a workspace `.venv` and targets `/workspace/.venv/bin/python` unless the caller explicitly supplies `--python`, `--system`, `--target`, or `--prefix`.

Net effect: `pip install torch` fails fast with a useful message at every casual entry point; `uv` is the one-and-only path; the bundle is genuinely self-contained on any base image with no host-side dependencies beyond bwrap + NVIDIA driver.

## 2. Out of scope

- Blocking `python -m pip` (expert hatch; would require `sitecustomize.py` that aborts the `pip` module on import and break legitimate introspection). Documented as "if you find yourself typing this, you're doing it wrong"; Gate 10b remains the safety net.
- Removing `py-pip` from `base-ml` (touches a Spack pin, gated by `AGENTS.md` "Critical invariants" §4). The shim strategy shadows `py-pip`'s `pip` via PATH order rather than removing it.
- A `DRACCUS_HOST_UV_BIN`-style override knob. The bundle is opinionated by design (see `§7.4`).
- Conda / Pixi / poetry integration. Out of thesis.

## 3. Prerequisites

| Requirement | How to verify |
|---|---|
| Commit `fefc6da` merged (ML-first PATH + draccus-uv) | `git log --oneline -1 -- bin/draccus-uv` |
| Gate 0 currently green | `./scripts/validate-static.sh` |
| User approval to modify `scripts/bootstrap-rootfs.sh` (AGENTS.md "What to avoid") | Recorded in tracker `* Decisions` |
| Outbound network to `github.com/astral-sh/uv/releases/...` from rootfs-build host | `curl -fsSI https://github.com/astral-sh/uv/releases` |
| Pre-existing rootfs can be rebuilt (or this workstream gates on next rootfs rebuild) | `df -h rootfs/`; bundle owner sign-off |

## 4. Phase decomposition

```
Phase 0  Decisions (uv pin, shim contents, venv post-process strategy)
Phase 1  Rootfs adds (uv binary; scripts/uv-version.env)
Phase 2  Shim infrastructure (shims/ dir, draccus-run PATH prepend, host_uv_* removal)
Phase 3  Venv post-process (draccus-project-init + lib/draccus-project.sh helper)
Phase 4  Validation (Gate 0 + Gate 1 checks)
Phase 5  Docs (DESIGN.md §8 split, AGENTS.md invariant addition, README appendix)
```

Phases are sequential. P2 deletes the host_uv block introduced in commit `fefc6da`; do not split that across phases (the simplification is the point).

## 5. Decisions an agent must record (not invent)

Recorded in `tracker.org * Decisions` before P1 starts. User sign-off required where noted.

1. **`uv` version + sha256** — pin in `scripts/uv-version.env` (new file). Bump cadence: bump-by-PR, same workflow as Spack pins. **Requires user sign-off** (becomes part of the foundation pin set alongside `cuda@13.1.1` and `py-torch@2.10.0`).
2. **Pip-shim message and exit code** — single-line stderr message (suggested: `pip is disabled inside draccus — use 'draccus-uv pip <args>' (or 'uv pip <args>' inside the namespace) instead`) and exit code (suggested: 2, matches the convention for "command rejected"). Decide the exact wording so the shim is grep-stable for Gate 1.
3. **Shim placement** — `shims/{pip,pip3}` at the bundle root, mounted RO at `/opt/draccus/shims` inside the namespace, PATH-prepended ahead of the views. Alternative considered (rootfs-only at `/usr/local/bin/pip`) **rejected** because Spack's `py-pip` ships `pip` into `base-ml/view/bin/` which sits earlier in PATH; the shim must shadow the view, which a top-of-PATH directory in the bundle achieves cleanly.
4. **Venv post-process strategy** — replace `.venv/bin/{pip,pip3,pip3.<N>}` with the same shim (rather than delete) so the error message remains uniform. Replacement happens in `lib/draccus-project.sh` via a new helper (`draccus_project_neutralize_pip`) called from both `bin/draccus-project-init` after `uv venv` and any future `draccus-uv venv` wrapper.

## 6. Invariants honored

Cite, don't redefine. Authoritative sources: `AGENTS.md` "Critical invariants", `DESIGN.md` §§4, 6, 8.

- **Canonical prefix contract** (`AGENTS.md` "Critical invariants" §3; `DESIGN.md` §4). All new namespace paths are under `/opt/draccus` (`/opt/draccus/shims`). No new host bind paths. The rootfs `uv` lives under the pinned rootfs at `/usr/local/bin/uv`, which is the same path contract as `nvcc` and `gcc`.
- **Two-layer Python model** (`AGENTS.md` "Two-layer Python model"). Unchanged in shape: Spack still owns the foundation, uv still owns project packages. This workstream pins `uv`-the-binary as a *foundation tool* (a rootfs artifact, sibling to `nvcc`), distinct from `uv`-managed-*packages* which remain the project layer. See `§7.2` for the "uv the binary vs uv the package manager" framing.
- **DO_NOT_SHADOW + tri-redundancy** (`AGENTS.md` "Critical invariants" §1). `scripts/validate_uv_layering.sh` array, `scripts/uv_overrides.txt`, `AGENTS.md` — unchanged. This workstream adds a fourth enforcement surface (the pip-shim) *and* keeps the post-hoc scanner (Gate 10b) as the safety net. See `§7.1`.
- **draccus-run RO vs draccus-build RW** (`AGENTS.md`; `DESIGN.md` §5). The shims directory is RO-bound; no consumer needs to write to it.
- **No `bootstrap-rootfs.sh` package adds without user approval** (`AGENTS.md` "What to avoid"). Adding `uv` and the pip shims to the rootfs is a deliberate exception that this workstream's P0 decision must call out and get sign-off on.
- **No `spack.yaml` drift** (`AGENTS.md` "What to avoid"). This workstream does NOT remove `py-pip` from `base-ml/spack.yaml`; the shim shadows it via PATH order.
- **Mandatory `validate-static.sh` after every edit** (`AGENTS.md`).

## 7. Necessary complexity

Things an engineer cannot derive from reading individual files alone.

### 7.1 Why pip-shim is the right enforcer (and where it isn't)

`draccus-uv` exports `UV_EXTRA_OVERRIDES` so the uv resolver refuses DO_NOT_SHADOW packages at *resolve* time. That covers every `uv` invocation. It does **not** cover:

- bare `pip install torch` inside `draccus-shell`,
- `source .venv/bin/activate && pip install torch` inside any project,
- `python -m pip install torch`.

The pip-shim closes the first two — these are the casual paths. The third (`python -m pip`) is the expert hatch and remains visible only to people who specifically reach for the module form. Gate 10b (`scripts/validate_uv_layering.sh`) is the post-hoc scanner: even if a determined user runs `python -m pip install torch`, Gate 10b's `uv.lock` scanner catches it before the project is considered valid. The complete enforcement chain is therefore:

| Layer | Surface | When it fires |
|---|---|---|
| Resolver constraint | `UV_EXTRA_OVERRIDES` via `draccus-uv` / `draccus-run` | At `uv lock` / `uv pip install` time |
| Command shim | `shims/pip`, `shims/pip3`, venv-post-process pip stubs | Any `pip` / `pip3` invocation |
| Static scanner | Gate 10b `validate_uv_layering.sh` on `uv.lock` | At validation time |
| Runtime probe | `validate-project-overlay.sh` checks `torch.__file__` | At Gate 10 |

Removing any one leaves a hole. Document this in `DESIGN.md §8` when P5 lands.

### 7.2 `uv`-the-binary vs `uv`-managed-packages

This is the conceptual confusion the workstream must prevent. After P5, `DESIGN.md §8` should state explicitly:

- **`uv`-the-binary** is a *foundation tool* — pinned, immutable at runtime, lives in the rootfs alongside `nvcc` and `gcc`. Bumping it is a one-line PR to `scripts/uv-version.env` + rootfs rebuild + user sign-off, same workflow as bumping any Spack pin.
- **`uv`-managed-packages** are *project layer* — fast-moving, per-project, `uv.lock`-tracked. Bumping them is a normal project commit, no foundation involvement.

Researchers who want a newer `uv` follow the same path as wanting a newer `torch`: file a foundation bump request. There is no in-flight override.

### 7.3 Why PATH ordering for the shim, not removal of `py-pip`

Removing `py-pip` from `envs/base-ml/spack.yaml` would be the "clean" answer but it:
- requires touching a Spack pin (gated by AGENTS.md);
- breaks any future Spack package that depends on `py-pip` being a build-time tool;
- creates a divergence between Spack's view and "real" Python installs that surprises tooling.

Prepending `/opt/draccus/shims` to PATH inside `draccus-run` is one line of change, leaves Spack alone, and gives a uniform "shim directory" home for any future intercept (`easy_install`, `conda`, etc.). The PATH ordering inside the namespace becomes:

```
/opt/draccus/shims                    <-- new: pip, pip3 → error
/opt/draccus/view/base-ml/bin         <-- base-ml: python, ipython, py-pip's pip (shadowed)
/opt/draccus/view/base-sys/bin
<rootfs cuda bins>
/usr/local/sbin
/usr/local/bin                        <-- rootfs: uv lives here
/usr/sbin
/usr/bin
/sbin
/bin
```

### 7.4 Why no `DRACCUS_HOST_UV_BIN` override

Considered and rejected. The bundle's thesis is "distraction-free dev-prod parity"; every override is a knob that must be tested, documented, and reasoned about. The rationale "what if someone needs a newer uv" is the same as "what if someone needs a newer torch" — and the answer is the same: bump the pin in a PR, rebuild the foundation, ship to all consumers atomically. Override knobs let one researcher's environment diverge from another's; that *is* the distraction the thesis fights against.

### 7.5 Venv post-process: replace, don't delete

`uv venv --system-site-packages .venv` creates `.venv/bin/pip`, `.venv/bin/pip3`, and `.venv/bin/pip3.<N>` as small wrappers. Deleting them would (a) make `pip --version` exit with "command not found" instead of the deliberate "use draccus-uv" message and (b) potentially surprise tooling that probes for `.venv/bin/pip` existence as a venv-validity signal. Replacing them with the same shim keeps the message uniform and the file present.

The helper lives in `lib/draccus-project.sh` (`draccus_project_neutralize_pip`) so both `bin/draccus-project-init` and any future `draccus-uv venv` wrapper call the same code. **Do not duplicate the shim contents** into the helper; the helper should `cp` from a single source-of-truth file (the same `shims/pip` that's bind-mounted into the namespace) — Gate 0 enforces.

## 8. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| `uv` version drift between bundles built at different times | Medium | Pin sha256 in `scripts/uv-version.env`; `bootstrap-rootfs.sh` hard-fails on checksum mismatch |
| `astral-sh/uv` GitHub release URL changes | Low | Pin to the GH releases CDN path, cache the artifact in `state/cache/` after first download |
| Spack later adds a new package whose binary collides with a shim | Low | Gate 0 check: shims/* names cannot match any base-sys/base-ml view binary name |
| Researcher's existing project venv (pre-workstream) has live `.venv/bin/pip` | Medium | `draccus-uv venv` and `draccus-project-init` post-process on creation; document one-liner for retrofit (`shims/pip` → `.venv/bin/pip{,3}`) |
| `python -m pip install torch` slipping through | Medium | Documented expert hatch; Gate 10b catches the lock-file footprint |
| Rootfs download interruption mid-bootstrap | Low | `bootstrap-rootfs.sh` retries with exponential backoff; final sha256 verify |
| Shim message gets stale ("use draccus-uv pip ..." but interface changes) | Low | Shim references `draccus-uv` by name; Gate 0 checks the wrapper still exists |

## 9. Definition of Done (whole workstream)

- All tasks in `tracker.org` marked `DONE`.
- `scripts/uv-version.env` exists with pinned `UV_VERSION` + `UV_SHA256`; user-approved.
- `scripts/bootstrap-rootfs.sh` downloads, verifies, and installs `uv` at `rootfs/usr/local/bin/uv`.
- `shims/pip` and `shims/pip3` exist at bundle root, executable, identical content (or `pip3` is a symlink), with the agreed error message.
- `bin/draccus-run` has the `host_uv_*` block deleted and PATH prepends `/opt/draccus/shims`.
- `bin/draccus-uv` is a thin wrapper that sources `lib/draccus-uv.sh`.
- `lib/draccus-uv.sh` auto-targets workspace `.venv` for `draccus-uv pip install/sync/uninstall` unless the caller supplies an explicit uv pip target.
- `lib/draccus-project.sh` exports `draccus_project_neutralize_pip`; called from `bin/draccus-project-init` after `uv venv`.
- `./scripts/validate-static.sh` passes; new Gate 0 checks: shims executable + content sentinel; `scripts/uv-version.env` parseable; `bin/draccus-run` PATH prepend present; `bin/draccus-uv` line count = 3; `bin/draccus-run` has no `DRACCUS_HOST_UV_BIN` reference.
- `bin/draccus-probe` (Gate 1) passes: `command -v uv → /usr/local/bin/uv`; `command -v pip → /opt/draccus/shims/pip`; running `pip` exits with the agreed code and message.
- `DESIGN.md §8` updated with `§7.1` enforcement chain and `§7.2` binary-vs-packages framing.
- `AGENTS.md` "Critical invariants" gains a line: "pip is disabled inside the namespace; use draccus-uv".
- `README.md` appendix lists the pinned `uv` version alongside `cuda@13.1.1` etc.
- `* Retrospective` written, including: did the shim ever produce a false-positive (legitimate caller blocked)? Any consumers (Spack package builds, CI scripts) that needed `python -m pip` instead?

## 10. Handoff protocol for agents

1. Read this file end-to-end, then `tracker.org` top-to-bottom.
2. Pick the lowest-numbered `TODO` whose `:DEPENDS:` are `DONE`.
3. Set `IN-PROGRESS`, fill `:OWNER:` + `:STARTED:`.
4. Execute. Append non-trivial command output as `** Log`; large logs go to `artifacts/`.
5. On completion: set `DONE`, fill `:FINISHED:`, list artifacts.
6. If blocked: set `BLOCKED`, write blocker under `** Blocker`, stop. Do not invent workarounds for §6 invariants. **Do not add a `DRACCUS_HOST_UV_BIN`-style override knob; that decision is settled (§7.4).**

When handing back: `git status` clean or intentional uncommitted state documented under `* Notes`.

## 11. File map for this workstream

```
.workstream/uv-in-rootfs/
├── design.md     this file
├── tracker.org   task tracker
└── artifacts/    bootstrap logs, uv download artifacts, shim test transcripts
```
