# Draccus - Persistent Claude Code Instructions

This is the persistent Claude Code instruction file for the Draccus repository. Draccus is a portable, reproducible, GPU-aware ML foundation using bubblewrap (bwrap) + Spack, documented in README.md and DESIGN.md.

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
Always create project venvs with: uv venv --python $(which python) --system-site-packages .venv

### 3. Canonical prefix contract

- Inside bwrap: paths must be under /opt/draccus or /work/src
- Never hardcode physical host paths (e.g. /data02/home/philip.yang/...) inside bwrap scripts
- DRACCUS_BUNDLE is resolved portably via lib/draccus-env.sh
- draccus-run mounts Spack read-only; draccus-build mounts it read-write

### 4. Pinned versions (do not change without explicit request)

- cuda@13.1.1, cudnn@9.17+, NCCL 2.29+
- py-torch@2.10.0 +cuda +cudnn +nccl +magma +distributed cuda_arch=100
- py-jax@0.9.1, py-jaxlib@0.9.1 +cuda cuda_arch=100
- python@3.12, TORCH_CUDA_ARCH_LIST=10.0 (NVIDIA B200)

### 5. cuda_arch=100 is sacrosanct

Target hardware is NVIDIA B200 (SM major=10). Do not change cuda_arch or TORCH_CUDA_ARCH_LIST without sign-off.

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
- Tracked source: bin/, lib/, scripts/, envs/*/spack.yaml, mise.toml, README.md, DESIGN.md, CLAUDE.md

## Quick reference

```bash
# Run Gate 0 (always safe, no GPU needed)
./scripts/validate-static.sh

# Interactive shell inside namespace
./bin/draccus-shell

# Build Spack environments
./bin/draccus-build bash -lc '. /opt/draccus/spack/share/spack/setup-env.sh && spack env activate base-ml && spack install'

# Full validation (GPU required)
./scripts/validate-all.sh
```
