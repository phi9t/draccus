# Draccus — Persistent Agent Instructions

This is the canonical instruction file for any coding agent working in the Draccus repository (Claude Code, Codex, Cursor, OpenHands, etc.). `CLAUDE.md` is a symlink to this file for tool compatibility — do not edit the symlink; edit `AGENTS.md`.

Draccus is a filesystem-isolated ML foundation that layers a pinned torch/jax/CUDA environment on top of any base image using bubblewrap (bwrap) + Spack. Documented in `README.md` and `DESIGN.md`.

## Workstream protocol — design, execute, track

All non-trivial work (anything beyond a single-file fix) goes through `.workstream/`. Do not start coding ad-hoc.

Layout:

```
.workstream/<feature-slug>/
├── design.md     high-level design: goal, scope, prerequisites, invariants, risks, DoD
├── tracker.org   org-mode task list (TODO / IN-PROGRESS / BLOCKED / DONE)
└── artifacts/    logs, lockfiles, command output produced during execution
```

Rules:

1. **Before starting a feature**, create `.workstream/<slug>/design.md` and `tracker.org`. Use `.workstream/spack-envs-bootstrap/` as the reference template.
2. **Before picking up an existing workstream**, read its `design.md` end-to-end and `tracker.org` top-to-bottom. Claim the lowest-numbered `TODO` whose `:DEPENDS:` are `DONE`. Set the task to `IN-PROGRESS`, fill `:OWNER:` and `:STARTED:`.
3. **While executing**, append non-trivial command output under the task as `** Log` or in the `:LOGBOOK:` drawer. Save large logs under `artifacts/`.
4. **On completion**, set the task to `DONE`, fill `:FINISHED:`, list produced artifacts.
5. **If blocked**, set to `BLOCKED`, write the blocker under `** Blocker`, stop. Never invent workarounds for the invariants below.
6. **Decisions** (pinned versions, mirror URLs, target tradeoffs) go under `* Decisions` in `tracker.org` *before* the dependent task starts. Get user sign-off when the invariants list says so.
7. **Handing back**: leave the working tree clean or document intentional uncommitted state in the tracker.

`.workstream/` is for in-flight planning and execution state; promote stable facts into `DESIGN.md` once a workstream completes.

**Skill:** the full protocol (templates, hard rules, two-mode workflow) lives in `.agents/skills/workstream/SKILL.md`. Claude Code users can invoke it as `/workstream`; other agents should read the SKILL.md directly before starting or continuing a workstream.

## Mandatory: Run after every edit

After editing ANY file in bin/, lib/, scripts/, envs/, or mise.toml, you MUST run:
```
./scripts/validate-static.sh
```
Do not propose a git commit until this passes.

## Critical invariants (never violate without explicit user approval)

### 1. Do-not-shadow list

These packages must ALWAYS resolve from /opt/draccus/view/base-ml, never from a .venv:
- torch, jax, jaxlib, numpy, scipy, triton, and any nvidia-* pip package

The authoritative list lives in scripts/validate_uv_layering.sh DO_NOT_SHADOW array.
To change it: get explicit user approval AND update both the array AND this file.

### 2. Two-layer Python model

- Spack (base-ml) owns: torch, jax, jaxlib, numpy, scipy, CUDA, cuDNN, NCCL, MKL, MAGMA, FFmpeg
- uv owns: transformers, datasets, accelerate, peft, trl, vllm, flash-attn, etc.

Never write uv pip install torch, uv pip install jax, uv pip install numpy, etc.
Always create project venvs with: draccus-uv venv --python $(which python) --system-site-packages .venv
Always install packages with: draccus-uv pip install transformers datasets accelerate

### 3. Canonical prefix contract

- Inside bwrap: paths must be under /opt/draccus or /workspace
- Never hardcode physical host paths (e.g. /data02/home/philip.yang/...) inside bwrap scripts
- DRACCUS_BUNDLE is resolved portably via lib/draccus-env.sh
- draccus-run mounts Spack read-only; draccus-build mounts it read-write

### 4. Pinned versions (do not change without explicit request)

- cuda@13.1.1, cudnn@9.17+, NCCL 2.29+
- py-torch@2.10.0 +cuda +cudnn +nccl ~magma +distributed cuda_arch=100
- py-jax@0.9.1, py-jaxlib@0.9.1 +cuda cuda_arch=100
- python@3.12, TORCH_CUDA_ARCH_LIST=10.0 (NVIDIA B200)

### 5. cuda_arch=100 is sacrosanct

Target hardware is NVIDIA B200 (SM major=10). Do not change cuda_arch or TORCH_CUDA_ARCH_LIST without sign-off.

### 6. Pip is disabled inside the namespace

Bare `pip` / `pip3` on `PATH` resolve to bundle shims under `shims/pip` that exit with a clear message directing you to `draccus-uv pip` (or `uv pip` inside the namespace). Authoritative shim source: `shims/pip`. To change this: get explicit user approval and update both `shims/pip` (and `shims/pip3`, which points at the same content) and this file.

## Validation gate sequence

| When | Gate | Command |
|------|------|---------|
| After any file edit | Gate 0 (no GPU) | ./scripts/validate-static.sh |
| After Spack env change | Gate 1 + 3/4 | ./bin/draccus-probe && ./scripts/validate-base-sys.sh |
| After base-ml change | Gates 6-9 | ./scripts/validate-base-ml.sh |
| Full acceptance | All 13 gates (GPU required) | ./scripts/validate-all.sh |
| Fast lint only | Lint only | mise run draccus-lint |

## What to avoid

- Do NOT run debootstrap or add packages to bootstrap-rootfs.sh without user approval
- Do NOT add packages to Spack specs without user approval
- Do NOT modify the DO_NOT_SHADOW list in validate_uv_layering.sh without user approval
- Do NOT commit rootfs/, state/, cache/, build/ (all in .gitignore)
- Do NOT hardcode DRACCUS_BUNDLE as a literal path in any script — always resolve via lib/draccus-env.sh
- Do NOT add --no-verify to git commit
- Do NOT skip pre-commit hooks

## Git hygiene

- .gitignore excludes: rootfs/, state/, cache/, build/, projects/, __pycache__/, *.pyc, .venv/
- Pre-commit hooks enforce Gate 0 on every commit (shellcheck, shfmt, ruff, yamllint)
- Tracked source: bin/ (including draccus-uv), lib/, scripts/ (including uv_overrides.txt), envs/*/spack.yaml, mise.toml, README.md, DESIGN.md, docs/, AGENTS.md (+ CLAUDE.md symlink), .cursor/ (project MCP + rules), .trae/ (Coco model notes; `.trae/artifacts/` is gitignored), .workstream/

## Cursor → Coco (TraeCLI) subagents

For **Cursor** sessions on this repo, isolated research/planning can be delegated to **Coco** via MCP:

- **Engineering doc:** `docs/coco-cursor-delegation.md` (architecture, verification, delegation contract).
- **Config:** `.cursor/mcp.json` starts `coco mcp serve` (stdio). Requires `coco` on `PATH`; restart Cursor after edits.
- **Usage:** Coco exposes an MCP tool **`Agent`** with `subagent_type` `Explore` (read-only), `Plan` (read-only planning), or `general-purpose` (full tools). Cursor may display it as `mcp_coco_Agent`.
- **Guidance:** `.cursor/rules/coco-delegation.mdc` — prefer `Explore`/`Plan`; put self-contained task text in `prompt` (subagents do not see the main chat); repeat **critical invariants** from this file inside the prompt when delegating Draccus work.
- **Models:** `.trae/COCO_MODELS.md` lists `/model` names smoke-tested with `./scripts/coco-probe-models.sh` (anti-fallback). Re-run after your TraeCLI catalog changes.

## Quick reference

```bash
# Run Gate 0 (always safe, no GPU needed)
./scripts/validate-static.sh

# Interactive ML sandbox (torch/jax python out of the box)
./bin/draccus-shell

# Run a command in the sandbox
./bin/draccus-run bash -lc 'python train.py'

# Add packages (with layering protection)
./bin/draccus-uv pip install transformers accelerate

# Debug shell (base-sys before base-ml on PATH)
./bin/draccus-debug-shell

# Build/update Spack environments (writable sandbox)
./bin/draccus-build bash -lc '. /opt/draccus/spack/share/spack/setup-env.sh && spack env activate base-ml && spack install'

# Run Gate 0 (always safe, no GPU needed)
./scripts/validate-static.sh

# Full validation (GPU required)
./scripts/validate-all.sh
```
