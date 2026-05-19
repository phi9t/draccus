# Draccus workstreams — index

This directory holds the per-feature planning and execution state for any non-trivial work in Draccus. The protocol — when to create a workstream, how to claim a task, what counts as `DONE` — is defined in **[AGENTS.md → Workstream protocol](../AGENTS.md)**; the full templates and rules live in **[`.agents/skills/workstream/SKILL.md`](../.agents/skills/workstream/SKILL.md)**. This file is the discovery layer: it tells you which workstreams are active right now, what to read first, and what the one outstanding code action is across the whole set.

Each workstream is a directory with a fixed shape:

```
.workstream/<slug>/
├── design.md       goal, scope, invariants honored, risks, definition of done
├── tracker.org     org-mode TODO / IN-PROGRESS / BLOCKED / DONE
└── artifacts/      logs, lockfiles, command output produced during execution
```

The `**Status:**` line at the top of each `design.md` is the canonical state surface. Three normalized forms are in use:

- `Closed (<date>) — <one-line outcome>`
- `Active — <one-line next action>`
- `Blocked on: <decision or external event>`

---

## Active

Workstreams where the next move is engineering or user action.

### `uv-overlay` — per-project uv venvs on top of `base-ml`

- **Status:** Active — empirical `uv sync --frozen` check (P3.1) + the only outstanding code gap across all workstreams (P4.3, see below).
- **Owner:** unassigned.
- **What it covers:** `projects/<name>/` shape, `bin/draccus-project-init`, `lib/draccus-project.sh`, `scripts/validate-project-overlay.sh` (Gate 10), `scripts/validate_uv_layering.sh` (Gate 10b), and a still-missing `scripts/validate-projects-all.sh` (Gate 10c).
- **Already shipped (Phases 0–3 partial):** project template (`projects/_template/`), `bin/draccus-project-init`, `lib/draccus-project.sh`, Gate 10, Gate 10b. `bin/draccus-uv` now sources `lib/draccus-uv.sh` (auto-venv on first `pip install` + foundation-package guards) — landed in commit [`96c7ce8`](../../../commits/96c7ce8).
- **Outstanding:** P3.1 (empirical `uv sync --frozen` smoke test), P4.1 (cache stress test), P4.2 (DESIGN.md §8 Mermaid), **P4.3 (Gate 10c — the one outstanding code action; see "Outstanding code actions" below)**, P5.* (DESIGN.md §8 decomposition + AGENTS.md pointer).
- **Read first:** [`uv-overlay/design.md`](uv-overlay/design.md) §1 (Goal), §4 (Phases), §7 (Necessary complexity); then [`uv-overlay/tracker.org`](uv-overlay/tracker.org) `* Status snapshot` + the P4.3 task.
- **Depends on:** `spack-envs-bootstrap/` (foundation), `uv-in-rootfs/` (resolver constraints + pip shim).

### `thesis-testable` — host contract + base-image matrix (Gate 14)

- **Status:** Blocked on: user sign-off on six P0 Decisions (host-contract floor, matrix members, runner shape, state distribution, smoke test scope, rootfs isolation contract).
- **Owner:** unassigned.
- **What it covers:** `scripts/validate-host-contract.sh`, `scripts/thesis-smoke-test.py`, a base-image matrix harness, Gate 14 (`DRACCUS_RUN_THESIS_MATRIX=1`), and a sentinel registry to keep negative tests stable across `uv`/`pip` upgrades.
- **Already shipped:** none — Phase 0 not yet entered; all 14 tasks `TODO`.
- **Outstanding:** all of it. P0.1 is the entry point — pick concrete values for the six decisions, then user sign-off on the four that require it (host-contract floor, runner shape, state distribution, rootfs isolation contract).
- **Read first:** [`thesis-testable/design.md`](thesis-testable/design.md) §1 (Goal), §5 (Decisions), §7.3 (the three matrix outcomes — `pass` / `contract-rejected` / `fail`); then [`thesis-testable/tracker.org`](thesis-testable/tracker.org) `* Decisions`.
- **Depends on:** `spack-envs-bootstrap/` (foundation must exist to validate), `uv-overlay/` (pip-block + Gate 10b exercised by negative tests), `uv-in-rootfs/` (rootfs `uv` + `shims/pip` are part of the contract being tested).

---

## Closed

Workstreams retained as audit trail. Each one shipped a concrete deliverable; the closure is recorded in the `**Status:**` line of the workstream's `design.md`.

### `spack-envs-bootstrap` — foundation install (Gates 0–9, 13)

- **Status:** Closed (2026-05-11) — Phases 0–5 DONE; `./scripts/validate-all.sh` exit 0 on B200 in ~137 s wall (warm cache).
- **Left behind:** pinned Spack at `86305d08…`; `envs/base-{sys,ml}/spack.yaml`; `envs/common/rootfs-externals.yaml`; lockfile snapshots at [`spack-envs-bootstrap/artifacts/{base-sys,base-ml}.spack.lock`](spack-envs-bootstrap/artifacts/). Hard-won workarounds (llvm@18 pin for jaxlib XLA, `~magma` on py-torch, `systemd-run --user` long-install harness, `finalize_rootfs_overlay` SONAME stubs, CUDA-installer SEGV → external from rootfs) documented in [`spack-envs-bootstrap/design.md §7`](spack-envs-bootstrap/design.md).
- **One residual:** P5.3 (buildcache push to a writable mirror) intentionally skipped — the configured mirror is public read-only. Reopen if/when a team-internal mirror lands.

### `uv-in-rootfs` — pinned `uv` + pip shimmed

- **Status:** Closed (2026-05-11) — Phases 0–5 DONE; `uv` pinned at `rootfs/usr/local/bin/uv` (version + sha256 in [`scripts/uv-version.env`](../scripts/uv-version.env)); `shims/{pip,pip3}` shadow Spack's `py-pip` via PATH order; `bin/draccus-uv` delegates to `lib/draccus-uv.sh` (auto-venv + foundation-package guards).
- **Left behind:** `scripts/uv-version.env`, `shims/`, `bin/draccus-uv` + `lib/draccus-uv.sh`, the `host-bin/` shim directory and host-overlay logic in `lib/draccus-nvidia-mounts.sh` (added in commit [`96c7ce8`](../../../commits/96c7ce8)). Enforcement chain (resolver constraint → command shim → static scanner → runtime probe) documented in [`uv-in-rootfs/design.md §7.1`](uv-in-rootfs/design.md).

### `repo-hygiene` — generated-state relocation

- **Status:** Closed (2026-05-14) — Phases 0–4 DONE; 182 GB of generated state moved out of the repo.
- **Left behind:** `rootfs/`, `state/`, `cache/`, `build/` are symlinks back to `~/.automata/draccus/repo-hygiene-20260514T062236Z/`. `.gitignore` rules tightened so source remains visible while generated paths stay out. Bundle is now usable for source review.
- **Meta workstream** — not part of the dependency graph above; sits alongside.

### `repo-commit-cleanup` — turn dirty tree into reviewable commits

- **Status:** Closed (2026-05-19) — Phases 0–4 DONE; 5 grouped commits ([`2c55835`](../../../commits/2c55835), [`6436277`](../../../commits/6436277), [`79d3eb7`](../../../commits/79d3eb7), [`ced9b92`](../../../commits/ced9b92), [`298bb59`](../../../commits/298bb59)) replaced the broad dirty tree.
- **Left behind:** `git status --short` clean; per-commit messages link back to the workstream artifacts they cleaned up. The NVIDIA-driver-bind-shadowing-rootfs-glibc fix landed during this workstream (commit [`2c55835`](../../../commits/2c55835)) — see [`repo-commit-cleanup/tracker.org`](repo-commit-cleanup/tracker.org) `* Decisions` for the diagnosis.
- **Meta workstream** — not part of the dependency graph above; sits alongside.

---

## Dependency graph

The four feature workstreams form a small DAG. The two meta workstreams (`repo-hygiene`, `repo-commit-cleanup`) sit alongside and are not part of it.

```
spack-envs-bootstrap   ── foundation install
        │
        ├──> uv-in-rootfs   ── pinned uv + pip shimmed
        │         │
        │         └──> uv-overlay   ── per-project uv venvs
        │                    │
        └─── ── ── ── ── ── ─┴──> thesis-testable   ── host contract + matrix
```

`thesis-testable` depends on all three predecessors because its smoke test exercises the foundation (base-ml), the pip-block (uv-in-rootfs), and the project overlay invariants (uv-overlay).

---

## Outstanding code actions

Across all six workstreams, **one** real implementation gap remains:

- **`scripts/validate-projects-all.sh` (Gate 10c)** — referenced from [`uv-overlay/design.md`](uv-overlay/design.md) §1 and from [`DESIGN.md §10`](../DESIGN.md), but the file does not exist; `scripts/validate-all.sh` does not call it. Owned by `uv-overlay/tracker.org` P4.3. Deliverables: (1) author the script (iterate every `projects/*/` excluding `_template/`, run `scripts/validate-project-overlay.sh` and `scripts/validate_uv_layering.sh` per project, exit non-zero on first failure); (2) wire into `scripts/validate-all.sh` as Gate 10c after Gate 10b; (3) Gate 0 picks up the new script via the existing shellcheck/shfmt list.

Everything else open in the active workstreams is documentation, validation runs, or user-decision sign-off — not new code.

---

## Starting a new workstream

Use the protocol in [`AGENTS.md`](../AGENTS.md) ("Workstream protocol — design, execute, track") and the templates in [`.agents/skills/workstream/SKILL.md`](../.agents/skills/workstream/SKILL.md). The canonical reference shape is [`spack-envs-bootstrap/`](spack-envs-bootstrap/) — design.md sections covering Goal / Out of scope / Prerequisites / Phase decomposition / Decisions / Invariants honored / Necessary complexity / Risk register / Definition of Done / Handoff / File map; tracker.org with `* Decisions` and one section per phase, tasks carrying `:OWNER:`, `:STARTED:`, `:FINISHED:`, `:DEPENDS:` (and `:SIGN_OFF:` on Decisions).

Update this file whenever a workstream lands or its status changes. The Status line in the workstream's `design.md` is the source of truth; this file mirrors it.
