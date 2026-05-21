# Draccus workstreams — index

This directory holds per-feature planning and execution state for non-trivial Draccus work. The protocol is defined in [AGENTS.md](../AGENTS.md); the full templates live in [`.agents/skills/workstream/SKILL.md`](../.agents/skills/workstream/SKILL.md).

Each workstream has:

```text
.workstream/<slug>/
├── design.md
├── tracker.org
└── artifacts/
```

The `**Status:**` line at the top of each `design.md` is the canonical status. Update this index whenever a workstream lands or that status changes.

---

## Active

### `single-command-cli` — one public `draccus` command

- **Status:** Active — Phase 5 legacy-entrypoint removal is done; next implementation action is Phase 6 documentation and acceptance.
- **Owner:** unassigned.
- **What it covers:** breaking CLI consolidation around `bin/draccus`; recorded `run`; native `shell`; project-bound `uv` and `notebook`; `doctor`; `build`; `project init`; initial `bundle show`; removal of legacy public entrypoints; Gate 0 and docs updates.
- **Read first:** [`single-command-cli/design.md`](single-command-cli/design.md), then [`single-command-cli/tracker.org`](single-command-cli/tracker.org) `* Decisions` and P6.
- **Depends on:** current runtime foundation and project overlay work.
- **Blocks:** `bundle-packaging`, `runtime-provenance`.

### `bundle-packaging` — local foundation bundle distribution

- **Status:** Active — blocked on `single-command-cli` landing the `draccus bundle` namespace.
- **Owner:** unassigned.
- **What it covers:** `draccus bundle pack/unpack/show`, default install under `~/.automata/draccus/bundles/default`, local archive manifest, include/exclude policy, unpack overwrite safety.
- **Read first:** [`bundle-packaging/design.md`](bundle-packaging/design.md), then [`bundle-packaging/tracker.org`](bundle-packaging/tracker.org).
- **Depends on:** `single-command-cli`.
- **Blocks:** `release-channels`.

### `runtime-provenance` — richer recorded run metadata

- **Status:** Active — blocked on `single-command-cli` recorded run directories.
- **Owner:** unassigned.
- **What it covers:** schema-versioned run metadata, git/project snapshot, selected env vars with redaction, foundation import provenance, bundle identity.
- **Read first:** [`runtime-provenance/design.md`](runtime-provenance/design.md), then [`runtime-provenance/tracker.org`](runtime-provenance/tracker.org).
- **Depends on:** `single-command-cli`.
- **Blocks:** `experiment-correctness`.

### `release-channels` — B200 foundation release evidence

- **Status:** Active — blocked on `bundle-packaging`.
- **Owner:** unassigned.
- **What it covers:** foundation release manifests, validation reports, compatibility contracts, reveal/check workflow, future named channel notes.
- **Read first:** [`release-channels/design.md`](release-channels/design.md), then [`release-channels/tracker.org`](release-channels/tracker.org).
- **Depends on:** `bundle-packaging`.

### `experiment-correctness` — replay, resume, locking, classification

- **Status:** Active — blocked on `runtime-provenance`.
- **Owner:** unassigned.
- **What it covers:** replay contract reconstruction, checkpoint sidecars, resume compatibility checks, data/artifact locking, coarse failure classification.
- **Read first:** [`experiment-correctness/design.md`](experiment-correctness/design.md), then [`experiment-correctness/tracker.org`](experiment-correctness/tracker.org).
- **Depends on:** `runtime-provenance`.

### `uv-overlay` — per-project uv venvs on top of `base-ml`

- **Status:** Active — empirical `uv sync --frozen` check (P3.1) + Gate 10c implementation gap (P4.3).
- **Owner:** unassigned.
- **What it covers:** project template, project init behavior, project overlay validation, uv layering validation, and the missing all-project validation gate.
- **Outstanding:** P3.1, P4.1, P4.2, P4.3, P5.*. `single-command-cli` will supersede the public command surface, so this workstream must be rechecked before continuing implementation.
- **Read first:** [`uv-overlay/design.md`](uv-overlay/design.md), then [`uv-overlay/tracker.org`](uv-overlay/tracker.org).
- **Depends on:** `spack-envs-bootstrap`, `uv-in-rootfs`.

### `thesis-testable` — host contract + base-image matrix

- **Status:** Blocked on: user sign-off on six P0 Decisions.
- **Owner:** unassigned.
- **What it covers:** host-contract validation, base-image matrix, Gate 14, and sentinel registry.
- **Read first:** [`thesis-testable/design.md`](thesis-testable/design.md), then [`thesis-testable/tracker.org`](thesis-testable/tracker.org) `* Decisions`.
- **Depends on:** `spack-envs-bootstrap`, `uv-overlay`, `uv-in-rootfs`.

---

## Program Dependency Graph

```text
single-command-cli
  |-- bundle-packaging
  |     `-- release-channels
  `-- runtime-provenance
        `-- experiment-correctness

spack-envs-bootstrap
  |-- uv-in-rootfs
  |     `-- uv-overlay
  `-- thesis-testable
```

`single-command-cli` is the next broad product action. Existing `uv-overlay` and `thesis-testable` work remains tracked, but any future task there must account for the new single-command public surface.

---

## Outstanding Code Actions

- **Next product action:** `single-command-cli` P6 documentation and acceptance.
- **Existing validation gap:** `uv-overlay` P4.3, the missing all-project validation gate. Revisit after CLI consolidation starts, because public command names and validation expectations will change.

---

## Closed

### `spack-envs-bootstrap` — foundation install

- **Status:** Closed (2026-05-11) — Phases 0-5 DONE; full validation passed on B200 warm cache.
- **Left behind:** pinned Spack, base-sys/base-ml manifests, lock snapshots, validation artifacts, and workaround documentation.

### `uv-in-rootfs` — pinned `uv` + pip shimmed

- **Status:** Closed (2026-05-11) — Phases 0-5 DONE; rootfs uv pin, pip shims, and uv wrapper behavior landed.

### `repo-hygiene` — generated-state relocation

- **Status:** Closed (2026-05-14) — generated rootfs/state/cache/build moved out of source tree.

### `repo-commit-cleanup` — turn dirty tree into reviewable commits

- **Status:** Closed (2026-05-19) — dirty tree replaced with grouped commits; status clean at close.

---

## Starting Or Continuing Work

Use [AGENTS.md](../AGENTS.md) and [`.agents/skills/workstream/SKILL.md`](../.agents/skills/workstream/SKILL.md). Before continuing an existing workstream, read its `design.md` and `tracker.org` top to bottom, then claim the lowest-numbered unblocked task.
