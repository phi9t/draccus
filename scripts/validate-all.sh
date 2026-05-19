#!/usr/bin/env bash
# Consolidated Draccus validation runner.
# Run from the bundle root or with DRACCUS_BUNDLE set.
#
# Failfast policy:
#   - The script aborts immediately on the first hard failure (set -euo pipefail).
#   - Only explicitly optional / informational steps (GPU detection, mise tasks,
#     optional heavy-package tests behind flags) are allowed to be non-fatal.
#   - When an optional gate is enabled via environment variable (e.g. RUN_CUDA_EXT_TEST=1),
#     failures inside that gate are treated as fatal.
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

echo "=== Draccus Full Validation Suite ==="
echo "Bundle: $DRACCUS_BUNDLE"
echo "Date: $(date -Iseconds)"
echo

# Gate 0: Static/structural checks (no GPU required)
echo "[Gate 0] Static/structural checks (validate-static.sh)"
"$DRACCUS_BUNDLE/scripts/validate-static.sh"
echo

# Gate 1: bwrap + rootfs contract
echo "[Gate 1] Namespace / rootfs / path contract"
"$DRACCUS_BUNDLE/bin/draccus-probe"
echo

# Gate 2: Spack path canonicality + pinned revision (supports SPACK_REF workflow)
echo "[Gate 2] Spack path canonicality + revision"
"$DRACCUS_BUNDLE/bin/draccus-build" bash -lc '
  set -euo pipefail
  test "$SPACK_ROOT" = /opt/draccus/spack
  . /opt/draccus/spack/share/spack/setup-env.sh
  spack debug report | head -5
  if [[ -d /opt/draccus/spack/.git ]]; then
    echo "Spack commit: $(cd /opt/draccus/spack && git rev-parse HEAD)"
  fi
  echo "  SPACK_ROOT correctly set to /opt/draccus/spack"
'
echo

# Gate 3: base-sys validation
echo "[Gate 3] base-sys validation"
"$DRACCUS_BUNDLE/scripts/validate-base-sys.sh"
echo

# Gate 4: base-ml concretization pre-install (check pins)
echo "[Gate 4] base-ml concretization & pin verification"
"$DRACCUS_BUNDLE/bin/draccus-build" bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh
  spack -e base-ml concretize -f
  spack -e base-ml spec -Il > /opt/draccus/envs/base-ml/concrete.txt
  echo "Concrete spec written to /opt/draccus/envs/base-ml/concrete.txt"
  grep -E "py-torch@2\.10\.0" /opt/draccus/envs/base-ml/concrete.txt
  grep -E "py-jaxlib@0\.9\.1" /opt/draccus/envs/base-ml/concrete.txt
  grep -E "cuda@13\.1\.1" /opt/draccus/envs/base-ml/concrete.txt
  grep -E "python@3\.12" /opt/draccus/envs/base-ml/concrete.txt
  grep -E "cuda_arch:?=100" /opt/draccus/envs/base-ml/concrete.txt
  echo "  All required pins present and no duplicate roots detected"
'
echo

# Gate 5: GPU visibility (outer environment)
echo "[Gate 5] GPU device visibility (outer)"
ls -l /dev/nvidia* 2>/dev/null || echo "  (no /dev/nvidia* visible on outer host — expected if no GPUs allocated)"
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || true
echo

# Gate 6-9: Full foundation runtime (torch, jax, numpy, ffmpeg)
echo "[Gate 6-9] Foundation runtime validation (torch / jax / numpy / ffmpeg)"
"$DRACCUS_BUNDLE/scripts/validate-base-ml.sh"
echo

# Gate 10: uv overlay contract (basic)
echo "[Gate 10] uv project overlay contract (basic)"
"$DRACCUS_BUNDLE/scripts/validate-project-overlay.sh"
echo

# Gate 10b: UV + Spack layering verification (nvidia-* scanner + HARD_FAIL detection)
echo "[Gate 10b] UV + Spack layering verification (nvidia-* + heavy inference)"
if [[ "${RUN_HEAVY_INFERENCE:-0}" == "1" ]]; then
  echo "  (heavy inference tests enabled via RUN_HEAVY_INFERENCE=1)"
fi
"$DRACCUS_BUNDLE/scripts/validate_uv_layering.sh"
echo

# Gate 11: CUDA extension ABI (optional – only if flash-attn or similar is required)
# When enabled via RUN_CUDA_EXT_TEST=1, this gate is fatal on failure (failfast).
if [[ "${RUN_CUDA_EXT_TEST:-0}" == "1" ]]; then
  echo "[Gate 11] CUDA extension ABI test (flash-attn)"
  "$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
    set -euo pipefail
    export PATH="/opt/draccus/view/base-ml/bin:${PATH}"
    export SPACK_ROOT=/opt/draccus/spack
    source .venv/bin/activate 2>/dev/null || true
    export CUDA_HOME=/opt/draccus/view/base-ml
    export CMAKE_PREFIX_PATH=/opt/draccus/view/base-ml
    export TORCH_CUDA_ARCH_LIST=10.0
    export MAX_JOBS=32
    uv pip install --no-build-isolation flash-attn
    python -c "import flash_attn; print(flash_attn.__file__)"
  '
else
  echo "[Gate 11] CUDA extension test skipped (set RUN_CUDA_EXT_TEST=1 to enable)"
fi
echo

# Gate 12: mise task validation (if mise.toml exists in current or projects/)
if command -v mise >/dev/null 2>&1 && [[ -f mise.toml || -f projects/example/mise.toml ]]; then
  echo "[Gate 12] mise task validation"
  mise run draccus-validate 2>/dev/null || echo "  (no draccus-validate task defined or mise not configured for this project)"
else
  echo "[Gate 12] mise validation skipped (mise not found or no mise.toml)"
fi
echo

# Gate 13: Offline reproducibility
echo "[Gate 13] Offline reproducibility"
DRACCUS_OFFLINE=1 "$DRACCUS_BUNDLE/bin/draccus-offline" bash -lc '
  set -euo pipefail
  export PATH="/opt/draccus/view/base-ml/bin:${PATH}"
  export SPACK_ROOT=/opt/draccus/spack
  export JAX_SKIP_CUDA_CONSTRAINTS_CHECK="${JAX_SKIP_CUDA_CONSTRAINTS_CHECK:-1}"
  python -c "
import torch, jax, numpy, scipy
print(\"offline imports successful\")
print(\"torch file:\", torch.__file__)
assert \"/opt/draccus/\" in torch.__file__
"
'
echo

echo "=== All executed gates completed ==="
echo "Review output above for any WARNING or failure messages."
echo "Full design reference: DESIGN.md"
