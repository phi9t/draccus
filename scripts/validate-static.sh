#!/usr/bin/env bash
# Gate 0: Fast, GPU-free static/structural validation for Draccus bwrap+Spack ML bundle
# This script performs static checks without requiring bwrap, Spack, or GPUs

set -euo pipefail

# Source draccus-env.sh to resolve DRACCUS_BUNDLE
# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

_draccus_uv_version_env_ok() {
  local envf="$DRACCUS_BUNDLE/scripts/uv-version.env"
  [[ -f "$envf" ]] || return 1
  # shellcheck disable=SC1091
  source "$envf"
  [[ "${UV_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
  [[ "${UV_SHA256:-}" =~ ^[a-f0-9]{64}$ ]] || return 1
}

_draccus_shims_dir_ok() {
  local f n=0
  shopt -s nullglob
  for f in "$DRACCUS_BUNDLE/shims"/*; do
    n=$((n + 1))
    case "$(basename "$f")" in
      pip | pip3) ;;
      *) return 1 ;;
    esac
  done
  shopt -u nullglob
  [[ "$n" -eq 2 ]]
}

_draccus_run_binds_shims() {
  grep -qF -- '--ro-bind "$DRACCUS_BUNDLE/shims" /opt/draccus/shims' "$DRACCUS_BUNDLE/bin/draccus-run"
}

# Counters for pass/fail
pass_count=0
fail_count=0

# Check function: runs a command and records pass/fail without exiting
# Usage: check <name> <command>
check() {
  local name="$1"
  local cmd="$2"

  if eval "$cmd" >/dev/null 2>&1; then
    echo "[PASS] $name"
    pass_count=$((pass_count + 1))
  else
    echo "[FAIL] $name"
    fail_count=$((fail_count + 1))
  fi
}

# ============================================================================
# CHECK 1 - Shell lint (shellcheck)
# ============================================================================

echo "=== CHECK 1: Shell lint (shellcheck) ==="

SHELL_FILES=(
  "$DRACCUS_BUNDLE/bin/draccus-build"
  "$DRACCUS_BUNDLE/bin/draccus-offline"
  "$DRACCUS_BUNDLE/bin/draccus-probe"
  "$DRACCUS_BUNDLE/bin/draccus-project-init"
  "$DRACCUS_BUNDLE/bin/draccus-run"
  "$DRACCUS_BUNDLE/bin/draccus-shell"
  "$DRACCUS_BUNDLE/bin/draccus-debug-shell"
  "$DRACCUS_BUNDLE/bin/draccus-uv"
  "$DRACCUS_BUNDLE/host-bin/nvidia-smi"
  "$DRACCUS_BUNDLE/lib/draccus-project.sh"
  "$DRACCUS_BUNDLE/lib/draccus-uv.sh"
  "$DRACCUS_BUNDLE/shims/pip"
  "$DRACCUS_BUNDLE/scripts/bootstrap-rootfs.sh"
  "$DRACCUS_BUNDLE/scripts/prune-draccus.sh"
  "$DRACCUS_BUNDLE/scripts/refresh-spack-lockfiles.sh"
  "$DRACCUS_BUNDLE/scripts/validate-all.sh"
  "$DRACCUS_BUNDLE/scripts/validate-base-ml.sh"
  "$DRACCUS_BUNDLE/scripts/validate-base-sys.sh"
  "$DRACCUS_BUNDLE/scripts/validate-project-overlay.sh"
  "$DRACCUS_BUNDLE/scripts/validate_uv_layering.sh"
  "$DRACCUS_BUNDLE/scripts/coco-probe-models.sh"
)

if command -v shellcheck >/dev/null 2>&1; then
  for f in "${SHELL_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      check "shellcheck: $(basename "$f")" "shellcheck --severity=warning \"$f\""
    fi
  done
else
  echo "[WARN] shellcheck not in PATH, skipping shell lint checks"
fi

echo ""

# ============================================================================
# CHECK 2 - Shell format (shfmt)
# ============================================================================

echo "=== CHECK 2: Shell format (shfmt) ==="

if command -v shfmt >/dev/null 2>&1; then
  for f in "${SHELL_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      check "shfmt: $(basename "$f")" "shfmt --diff -i 2 -ci -bn \"$f\""
    fi
  done
else
  echo "[WARN] shfmt not in PATH, skipping shell format checks"
fi

echo ""

# ============================================================================
# CHECK 3 - Python lint (ruff)
# ============================================================================

echo "=== CHECK 3: Python lint (ruff) ==="

if command -v ruff >/dev/null 2>&1; then
  if [[ -f "$DRACCUS_BUNDLE/scripts/validate_foundation.py" ]]; then
    check "ruff: validate_foundation.py" "ruff check \"$DRACCUS_BUNDLE/scripts/validate_foundation.py\""
  else
    echo "[WARN] validate_foundation.py not found, skipping"
  fi
else
  echo "[WARN] ruff not in PATH, skipping Python lint checks"
fi

echo ""

# ============================================================================
# CHECK 4 - YAML lint (yamllint)
# ============================================================================

echo "=== CHECK 4: YAML lint (yamllint) ==="

if command -v yamllint >/dev/null 2>&1; then
  if [[ -f "$DRACCUS_BUNDLE/.yamllint.yml" ]]; then
    YAMLLINT_CONFIG="$DRACCUS_BUNDLE/.yamllint.yml"
  else
    YAMLLINT_CONFIG=""
  fi

  # spack.yaml uses Spack-specific YAML conventions (version range syntax like "nccl@2.29: +cuda"
  # and list items at parent indent) that trigger yamllint errors. Structural validation is
  # handled by Check 5. Add other YAML files to YAMLLINT_FILES as they are introduced.
  YAMLLINT_FILES=()
  if [[ ${#YAMLLINT_FILES[@]} -eq 0 ]]; then
    echo "[NOTE] No additional YAML files to lint (spack.yaml excluded; validated by Check 5)"
  else
    for f in "${YAMLLINT_FILES[@]}"; do
      if [[ -f "$f" ]]; then
        if [[ -n "$YAMLLINT_CONFIG" ]]; then
          check "yamllint: $(basename "$f")" "yamllint -c \"$YAMLLINT_CONFIG\" \"$f\""
        else
          check "yamllint: $(basename "$f")" "yamllint \"$f\""
        fi
      fi
    done
  fi
else
  echo "[WARN] yamllint not in PATH, skipping YAML lint checks"
fi

echo ""

# ============================================================================
# CHECK 5 - Spack YAML structural check
# ============================================================================

echo "=== CHECK 5: Spack YAML structural check ==="

BASE_SYS_YAML="$DRACCUS_BUNDLE/envs/base-sys/spack.yaml"
BASE_ML_YAML="$DRACCUS_BUNDLE/envs/base-ml/spack.yaml"

# Verify files exist
check "spack.yaml exists: base-sys" "test -f \"$BASE_SYS_YAML\""
check "spack.yaml exists: base-ml" "test -f \"$BASE_ML_YAML\""

# Check base-sys/spack.yaml for required keys
check "base-sys: 'view:' present" "grep -q 'view:' \"$BASE_SYS_YAML\""
check "base-sys: 'concretizer:' present" "grep -q 'concretizer:' \"$BASE_SYS_YAML\""
check "base-sys: 'specs:' present" "grep -q 'specs:' \"$BASE_SYS_YAML\""

# Check base-ml/spack.yaml for required keys
check "base-ml: 'view:' present" "grep -q 'view:' \"$BASE_ML_YAML\""
check "base-ml: 'concretizer:' present" "grep -q 'concretizer:' \"$BASE_ML_YAML\""
check "base-ml: 'specs:' present" "grep -q 'specs:' \"$BASE_ML_YAML\""

# Enforce unified concretization graph (workspace policy; avoids duplicate-version solver churn).
check "base-sys: concretizer unify: true" "grep -qE '^[[:space:]]*unify:[[:space:]]*true[[:space:]]*$' \"$BASE_SYS_YAML\""
check "base-ml: concretizer unify: true" "grep -qE '^[[:space:]]*unify:[[:space:]]*true[[:space:]]*$' \"$BASE_ML_YAML\""

# Check for cuda_arch=100 in base-ml
check "base-ml: 'cuda_arch=100' present" "grep -q 'cuda_arch=100' \"$BASE_ML_YAML\""

# Check for python@3.12 in base-ml
check "base-ml: 'python@3.12' present" "grep -q 'python@3.12' \"$BASE_ML_YAML\""

echo ""

# ============================================================================
# CHECK 6 - Do-not-shadow consistency
# ============================================================================

echo "=== CHECK 6: Do-not-shadow consistency ==="

UV_LAYERING_SCRIPT="$DRACCUS_BUNDLE/scripts/validate_uv_layering.sh"

if [[ -f "$UV_LAYERING_SCRIPT" ]]; then
  REQUIRED_PACKAGES=("torch" "jax" "jaxlib" "numpy" "scipy" "triton")

  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if grep -o "DO_NOT_SHADOW" "$UV_LAYERING_SCRIPT" >/dev/null 2>&1 \
      && grep -A 10 "DO_NOT_SHADOW=" "$UV_LAYERING_SCRIPT" | grep -o "$pkg" >/dev/null 2>&1; then
      echo "[PASS] DO_NOT_SHADOW contains: $pkg"
      pass_count=$((pass_count + 1))
    else
      echo "[FAIL] DO_NOT_SHADOW missing: $pkg"
      fail_count=$((fail_count + 1))
    fi
  done
else
  echo "[FAIL] validate_uv_layering.sh not found"
  fail_count=$((fail_count + 1))
fi

echo ""

# ============================================================================
# CHECK 7 - Rootfs stamp
# ============================================================================

echo "=== CHECK 7: Rootfs stamp ==="

ROOTFS_DIR="$DRACCUS_BUNDLE/rootfs"
ROOTFS_STAMP="$ROOTFS_DIR/.draccus-cuda-docker-image"

if [[ -d "$ROOTFS_DIR" ]]; then
  check "rootfs stamp exists and is non-empty" "test -s \"$ROOTFS_STAMP\""
else
  echo "[NOTE] rootfs/ directory not yet bootstrapped, skipping stamp check"
fi

echo ""

# ============================================================================
# CHECK 8 - Launcher executability
# ============================================================================

echo "=== CHECK 8: Launcher executability ==="

LAUNCHERS=(
  "$DRACCUS_BUNDLE/bin/draccus-run"
  "$DRACCUS_BUNDLE/bin/draccus-build"
  "$DRACCUS_BUNDLE/bin/draccus-offline"
  "$DRACCUS_BUNDLE/bin/draccus-project-init"
  "$DRACCUS_BUNDLE/bin/draccus-shell"
  "$DRACCUS_BUNDLE/bin/draccus-debug-shell"
  "$DRACCUS_BUNDLE/bin/draccus-probe"
  "$DRACCUS_BUNDLE/bin/draccus-uv"
)

for launcher in "${LAUNCHERS[@]}"; do
  check "executable: $(basename "$launcher")" "test -x \"$launcher\""
done

echo ""

# ============================================================================
# CHECK 9 - pinned uv + pip shims (static)
# ============================================================================

echo "=== CHECK 9: pinned uv + pip shims (static) ==="

check "uv-version.env exists" "test -f \"$DRACCUS_BUNDLE/scripts/uv-version.env\""
check "uv-version: semver + 64-hex sha256" "_draccus_uv_version_env_ok"
check "shims directory: exactly pip + pip3" "_draccus_shims_dir_ok"
check "shims/pip executable" "test -x \"$DRACCUS_BUNDLE/shims/pip\""
check "shims/pip3 present" "test -e \"$DRACCUS_BUNDLE/shims/pip3\""
check "shims/pip contains sentinel" "grep -Fq 'pip is disabled inside draccus' \"$DRACCUS_BUNDLE/shims/pip\""
check "shims/pip3 contains sentinel" "grep -Fq 'pip is disabled inside draccus' \"$DRACCUS_BUNDLE/shims/pip3\""
check "draccus-run ro-binds bundle shims to /opt/draccus/shims" "_draccus_run_binds_shims"
check "draccus-run ro-binds host-bin to /opt/draccus/host-bin" "grep -qF ' /opt/draccus/host-bin' \"$DRACCUS_BUNDLE/bin/draccus-run\""
check "draccus-run PATH leads with /opt/draccus/shims" "grep -qF 'draccus_path_views=\"/opt/draccus/shims:' \"$DRACCUS_BUNDLE/bin/draccus-run\""
check "draccus-run PATH includes host-bin" "grep -qF '/opt/draccus/host-bin' \"$DRACCUS_BUNDLE/bin/draccus-run\""
check "draccus-run has no host_uv / DRACCUS_HOST_UV_BIN" "! grep -qE 'DRACCUS_HOST_UV_BIN|host_uv_' \"$DRACCUS_BUNDLE/bin/draccus-run\""
check "host-bin/nvidia-smi fallback executable" "test -x \"$DRACCUS_BUNDLE/host-bin/nvidia-smi\""
check "draccus-uv delegates behavior to lib/draccus-uv.sh" "grep -qF 'lib/draccus-uv.sh' \"$DRACCUS_BUNDLE/bin/draccus-uv\""
check "draccus-uv auto-targets workspace .venv for pip installs" "grep -qF -- '--python /workspace/.venv/bin/python' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""
check "draccus-uv blocks direct foundation package installs" "grep -qF 'refusing to install foundation package' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""
check "draccus-uv audits resolved install plans" "grep -qF -- '--dry-run' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""

echo ""

# ============================================================================
# CHECK 10 - bwrap probe (optional)
# ============================================================================

echo "=== CHECK 10: bwrap probe (optional) ==="

if command -v bwrap >/dev/null 2>&1; then
  echo "[INFO] bwrap available, running draccus-probe..."
  if "$DRACCUS_BUNDLE/bin/draccus-probe"; then
    echo "[PASS] draccus-probe completed successfully"
    pass_count=$((pass_count + 1))
  else
    echo "[FAIL] draccus-probe failed"
    fail_count=$((fail_count + 1))
  fi
else
  echo "[NOTE] bwrap not in PATH, skipping probe"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo "========================================"
echo "           VALIDATION SUMMARY           "
echo "========================================"
echo "Passed: $pass_count"
echo "Failed: $fail_count"
echo "========================================"

if [[ $fail_count -gt 0 ]]; then
  echo "RESULT: FAILURE ($fail_count check(s) failed)"
  exit 1
else
  echo "RESULT: SUCCESS (all checks passed)"
  exit 0
fi
