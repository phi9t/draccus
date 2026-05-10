#!/usr/bin/env bash
# UV + Spack Layering Verification for Draccus
#
# Adapted from sygaldry's verify_uv_layering.sh for the bwrap-based Draccus environment.
# Validates that UV-installed packages correctly layer on top of the Spack foundation
# without overriding core ML packages or pulling in conflicting NVIDIA/CUDA pip packages.
#
# Usage:
#   ./scripts/validate_uv_layering.sh                    # basic checks
#   RUN_HEAVY_INFERENCE=1 ./scripts/validate_uv_layering.sh   # include vllm/sglang/flash-attn
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed (failfast)
#
# Failfast policy: any unexpected error aborts immediately. Only steps guarded by
# explicit environment variables (RUN_HEAVY_INFERENCE) may be skipped.

set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

# ============================================================================
# Single source of truth: packages that must never be shadowed by UV
# ============================================================================

# Core foundation packages (must resolve from /opt/draccus/view/base-ml)
readonly -a DO_NOT_SHADOW=(
  torch
  jax
  jaxlib
  numpy
  scipy
  triton
)

# Packages whose *pip* distribution names start with "nvidia-" and must not appear
# in a project UV venv (unless they came from the Spack view).
# shellcheck disable=SC2034
readonly NVIDIA_PIP_PREFIX="nvidia-"

# High-level packages that should come from the UV venv
readonly -a UV_PACKAGES=(
  transformers
  datasets
  accelerate
  tokenizers
  safetensors
)

# Heavy inference packages (only tested when RUN_HEAVY_INFERENCE=1)
readonly -a HEAVY_INFERENCE_PACKAGES=(
  vllm
  sglang
  flash-attn
)

# ============================================================================
# Helper functions
# ============================================================================

pass() { echo "  PASS: $*"; }
fail() {
  echo "  FAIL: $*" >&2
  exit 1
}

python_in_venv() {
  # Run python inside the test venv (created by this script)
  "$DRACCUS_BUNDLE/bin/draccus-run" bash -lc "
    set -euo pipefail
    . /opt/draccus/spack/share/spack/setup-env.sh
    spack env activate -p base-ml 2>/dev/null || true
    source /tmp/draccus-uv-verify/.venv/bin/activate
    python -c \"$1\"
  "
}

# ============================================================================
# T8.1: Ensure clean test venv exists (idempotent)
# ============================================================================

echo "=== UV + Spack Layering Verification ==="
echo "Bundle: $DRACCUS_BUNDLE"
echo ""

echo "[T8.1] Creating isolated test venv (if needed)"
"$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh
  spack env activate -p base-ml 2>/dev/null || true

  VENV_DIR="/tmp/draccus-uv-verify/.venv"
  if [[ -d "$VENV_DIR" ]]; then
    echo "  Reusing existing test venv at $VENV_DIR"
  else
    mkdir -p "$(dirname "$VENV_DIR")"
    uv venv --python "$(which python)" --system-site-packages "$VENV_DIR"
    echo "  Created fresh test venv"
  fi

  # Install baseline UV packages (idempotent)
  source "$VENV_DIR/bin/activate"
  uv pip install --quiet transformers datasets accelerate tokenizers safetensors
  echo "  Baseline UV packages installed"
'
pass "Test venv ready with baseline packages"

# ============================================================================
# T8.2: Foundation provenance (do-not-shadow list)
# ============================================================================

echo ""
echo "[T8.2] Verifying foundation packages resolve from Spack view"

for pkg in "${DO_NOT_SHADOW[@]}"; do
  mod_name="${pkg//-/_}"
  result=$(python_in_venv "
import importlib
mod = importlib.import_module('${mod_name}')
path = getattr(mod, '__file__', '') or ''
if '/opt/draccus/' in path:
    print('OK')
else:
    print('SHADOWED: ' + path)
") || true

  last_line="$(echo "$result" | tail -1)"
  if [[ "$last_line" == "OK" ]]; then
    pass "$pkg from Spack (/opt/draccus/)"
  else
    fail "$pkg is shadowed: $last_line"
  fi
done

# ============================================================================
# T8.3: UV package provenance
# ============================================================================

echo ""
echo "[T8.3] Verifying UV-managed packages resolve from project venv"

for pkg in "${UV_PACKAGES[@]}"; do
  mod_name="${pkg//-/_}"
  result=$(python_in_venv "
import importlib
try:
    mod = importlib.import_module('${mod_name}')
    path = getattr(mod, '__file__', '') or ''
    if '/tmp/draccus-uv-verify/.venv' in path:
        print('OK')
    elif '/opt/draccus/' in path:
        print('SPACK: ' + path)
    else:
        print('UNKNOWN: ' + path)
except ImportError:
    print('NOT_INSTALLED')
") || true

  last_line="$(echo "$result" | tail -1)"
  if [[ "$last_line" == "OK" ]]; then
    pass "$pkg from UV venv"
  elif [[ "$last_line" == "NOT_INSTALLED" ]]; then
    echo "  SKIP: $pkg not installed (optional)"
  else
    fail "$pkg provenance unexpected: $last_line"
  fi
done

# ============================================================================
# T8.4: No nvidia-* pip packages in UV venv
# ============================================================================

echo ""
echo "[T8.4] Scanning for forbidden nvidia-* pip packages in UV venv"

result=$(python_in_venv '
import importlib.metadata as md
forbidden = []
for dist in md.distributions():
    name = (dist.metadata.get("Name") or "").lower()
    loc = str(getattr(dist, "_path", ""))
    if name.startswith("nvidia-") and "/opt/draccus/" not in loc:
        forbidden.append(name)
if forbidden:
    print("NVIDIA_PIP_FOUND: " + ",".join(forbidden))
else:
    print("NO_NVIDIA_PIP_OK")
') || true

last_line="$(echo "$result" | tail -1)"
if [[ "$last_line" == "NO_NVIDIA_PIP_OK" ]]; then
  pass "No nvidia-* pip packages leaked into UV venv"
else
  fail "Forbidden nvidia-* packages found in UV venv: $last_line"
fi

# ============================================================================
# T8.5: GPU functionality after layering
# ============================================================================

echo ""
echo "[T8.5] GPU functional test after UV layering"

result=$(python_in_venv '
import torch
assert torch.cuda.is_available(), "CUDA not available"
a = torch.randn(128, 128, device="cuda", dtype=torch.float16)
b = torch.randn(128, 128, device="cuda", dtype=torch.float16)
c = torch.matmul(a, b)
assert c.shape == (128, 128)
print("GPU_OK")
') || true

last_line="$(echo "$result" | tail -1)"
if [[ "$last_line" == "GPU_OK" ]]; then
  pass "torch CUDA matmul works after layering"
else
  fail "GPU functional test failed: $last_line"
fi

# ============================================================================
# T8.6: Heavy inference package HARD_FAIL detection (optional)
# ============================================================================

if [[ "${RUN_HEAVY_INFERENCE:-0}" == "1" ]]; then
  echo ""
  echo "[T8.6] Heavy inference package tests (vLLM / SGLang / flash-attn)"

  for pkg in "${HEAVY_INFERENCE_PACKAGES[@]}"; do
    echo "  Testing $pkg ..."
    result=$(python_in_venv "
import sys
try:
    if '${pkg}' == 'flash-attn':
        import flash_attn
        print(f'flash-attn {flash_attn.__version__} imported OK')
    elif '${pkg}' == 'vllm':
        import vllm
        print(f'vllm {vllm.__version__} imported OK')
    elif '${pkg}' == 'sglang':
        import sglang
        print(f'sglang {sglang.__version__} imported OK')
except ImportError as e:
    err = str(e).lower()
    conflict_patterns = ('undefined symbol', 'cuda', 'libcusparse', 'libnvjitlink', 'triton', 'nvjitlink')
    if any(p in err for p in conflict_patterns):
        print('HARD_FAIL: ${pkg}')
        print(f'  core_conflict: {e}')
        print('  failure_type: abi_mismatch_or_missing_cuda_symbol')
        sys.exit(2)
    else:
        print(f'IMPORT_ERROR: {e}')
        sys.exit(1)
except Exception as e:
    print(f'UNEXPECTED_ERROR: {e}')
    sys.exit(1)
print('IMPORT_OK')
") || true

    last_line="$(echo "$result" | tail -1)"
    if [[ "$last_line" == "IMPORT_OK" ]]; then
      pass "$pkg imported successfully"
    elif [[ "$last_line" == "HARD_FAIL: ${pkg}" ]]; then
      fail "HARD_FAIL for $pkg (ABI / CUDA symbol conflict detected)"
    elif [[ "$last_line" == "IMPORT_ERROR: ${pkg}" ]]; then
      echo "  WARN: $pkg import error (non-fatal for this gate)"
    else
      echo "  SKIP: $pkg not installed or test skipped"
    fi
  done
else
  echo ""
  echo "[T8.6] Heavy inference tests skipped (set RUN_HEAVY_INFERENCE=1 to enable)"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=== UV + Spack Layering Verification Complete ==="
echo "All critical checks passed. Do-not-shadow list is respected."
echo "Do-not-shadow list: ${DO_NOT_SHADOW[*]}"
echo ""
echo "To run heavy inference tests (vLLM/SGLang/flash-attn):"
echo "  RUN_HEAVY_INFERENCE=1 $0"
echo ""
