# Workstream: Single Command CLI

**Owner:** unassigned
**Status:** Done - single `draccus` command surface landed and accepted on 2026-05-21.
**Target completion:** Unscheduled
**Related docs:** `docs/training-substrate-roadmap.md`, `DESIGN.md`, `README.md`, `AGENTS.md`

## 1. Goal

Make `bin/draccus` the only public Draccus entrypoint. The CLI must provide a polished daily workflow, remove the legacy per-command entrypoints, record `draccus run` executions by default, preserve the native interactive shell experience, and update validation and docs so the new surface is the only supported interface.

## 2. Out of scope

- Remote bundle registries or named channels.
- Deep run provenance beyond operational records.
- Replay/resume/checkpoint compatibility.
- Raw ad-hoc command execution outside projects.
- A Rust CLI or TUI implementation; this workstream keeps the first CLI Bash-based.

## 3. Prerequisites (Phase 0)

| Requirement | How to verify |
|---|---|
| Working tree scope understood | `git status --short` |
| Existing shell/runtime contract understood | Read `DESIGN.md` launcher/runtime sections |
| Current Gate 0 baseline known | `./scripts/validate-static.sh` |
| Default shared state root available | `test -d ~/.automata/draccus || mkdir -p ~/.automata/draccus` |
| GPU host available for doctor checks | `nvidia-smi -L` |

## 4. Phase decomposition

1. Phase 0 - Preflight and decisions.
2. Phase 1 - CLI router and shared library boundaries.
3. Phase 2 - Project config and initialization.
4. Phase 3 - Shell, build, uv, notebook, and doctor commands.
5. Phase 4 - Recorded `run`.
6. Phase 5 - Remove legacy entrypoints and update validation.
7. Phase 6 - Documentation and acceptance.

## 5. Key decisions an agent must record

1. Final command grammar and help text scope.
2. `draccus.yaml` first schema version.
3. Project id hash algorithm and run id format.
4. Default shared root path behavior.
5. Legacy entrypoint removal list.

## 6. Critical invariants

From `AGENTS.md`, do not violate without explicit user approval:

- Do-not-shadow list: `torch`, `jax`, `jaxlib`, `numpy`, `scipy`, `triton`, and any `nvidia-*` pip package must resolve from `/opt/draccus/view/base-ml`, never from a `.venv`.
- Two-layer Python model: Spack owns torch, jax, jaxlib, numpy, scipy, CUDA, cuDNN, NCCL, MKL, MAGMA, FFmpeg; uv owns fast-moving project packages. Never install foundation packages with uv.
- Canonical prefix contract: inside bwrap, paths must be under `/opt/draccus` or `/workspace`; do not hardcode physical host paths in bwrap scripts.
- Pinned versions: `cuda@13.1.1`, `cudnn@9.17+`, `NCCL 2.29+`, `py-torch@2.10.0`, `py-jax@0.9.1`, `py-jaxlib@0.9.1`, `python@3.12`, `TORCH_CUDA_ARCH_LIST=10.0`.
- `cuda_arch=100` is sacrosanct.
- Pip is disabled inside the namespace.
- After editing any file in `bin/`, `lib/`, `scripts/`, `envs/`, or `mise.toml`, run `./scripts/validate-static.sh`.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Breaking removal leaves stale docs or scripts | High | Phase 5 explicitly searches and updates repo references; Gate 0 enforces new surface. |
| Bash CLI becomes hard to maintain | Medium | Keep `bin/draccus` as dispatcher; place reusable behavior in `lib/`. |
| Recording changes command semantics | Medium | Stream and tee output; preserve child exit code exactly. |
| Shell UX regresses | Medium | Preserve current zsh/base-ml/project-venv flow; shell remains interactive-only and unrecorded. |
| Project requirement feels heavy | Low | `project init` creates `draccus.yaml`, generic `pyproject.toml`, `.venv`, and `uv.lock` in one command. |

## 8. Definition of Done (whole workstream)

- `bin/draccus` implements the approved first command surface.
- Legacy per-command entrypoints are removed.
- `draccus run` records operational run artifacts by default and exits with the child exit code.
- `draccus shell` remains native, interactive-only, and works outside a project.
- `draccus project init` writes a minimal `draccus.yaml`, generic `pyproject.toml`, `.venv`, and `uv.lock`.
- `draccus doctor` fails on missing GPU by default and supports `--json`.
- `./scripts/validate-static.sh` passes and enforces the new command surface.
- README, DESIGN, and `docs/training-substrate-roadmap.md` describe only the new public CLI.
- Tracker tasks are `DONE`; retrospective is filled.

## 9. Handoff protocol

Use `AGENTS.md` workstream protocol. Before claiming a task, read this design, `tracker.org`, and the relevant runtime sections in `DESIGN.md`. Any edit under `bin/`, `lib/`, or `scripts/` requires Gate 0 before marking the task `DONE`.

## 10. File map

```text
.workstream/single-command-cli/
├── design.md
├── tracker.org
└── artifacts/
```
