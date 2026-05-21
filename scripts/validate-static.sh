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

_draccus_no_legacy_public_entrypoints() {
  local legacy
  for legacy in \
    draccus-run \
    draccus-build \
    draccus-shell \
    draccus-uv \
    draccus-probe \
    draccus-project-init \
    draccus-debug-shell \
    draccus-offline; do
    [[ ! -e "$DRACCUS_BUNDLE/bin/$legacy" ]] || return 1
  done
}

_draccus_cli_respects_bundle_env() {
  local tmpdir output status ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-selected-bundle.XXXXXX")"

  set +e
  output="$(env DRACCUS_BUNDLE="$tmpdir" "$DRACCUS_BUNDLE/bin/draccus" bundle show --json 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]] \
    && printf '%s\n' "$output" | python3 -m json.tool >/dev/null \
    && [[ "$output" == *"\"bundle\":\"$tmpdir\""* ]]; then
    ok=0
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_no_stale_active_public_refs() {
  local files=(
    "$DRACCUS_BUNDLE/AGENTS.md"
    "$DRACCUS_BUNDLE/DESIGN.md"
    "$DRACCUS_BUNDLE/README.md"
    "$DRACCUS_BUNDLE/.pre-commit-config.yaml"
    "$DRACCUS_BUNDLE/docs/superpowers/plans/2026-05-21-single-command-cli.md"
    "$DRACCUS_BUNDLE/docs/tech-blog-hello-draccus.md"
    "$DRACCUS_BUNDLE/mise.toml"
    "$DRACCUS_BUNDLE/projects/_template/.gitignore"
    "$DRACCUS_BUNDLE/projects/_template/.python-version"
    "$DRACCUS_BUNDLE/projects/_template/README.md"
    "$DRACCUS_BUNDLE/projects/_template/draccus.yaml"
    "$DRACCUS_BUNDLE/projects/_template/pyproject.toml"
    "$DRACCUS_BUNDLE/scripts/validate-all.sh"
    "$DRACCUS_BUNDLE/shims/pip"
    "$DRACCUS_BUNDLE/shims/pip3"
  )
  local pattern='(^|[^[:alnum:]_./-])(bin/|\./bin/)?draccus-(run|build|shell|uv|probe|project-init|debug-shell|offline)([^[:alnum:]_./-]|$)|bin/draccus-\*|DRACCUS_BUNDLE[[:space:]]*=[[:space:]]*"/data02/home/philip.yang/draccus"'

  ! grep -nE "$pattern" "${files[@]}" >/dev/null
}

_draccus_run_binds_shims() {
  grep -qF -- '--ro-bind "$DRACCUS_BUNDLE/shims" /opt/draccus/shims' "$DRACCUS_RUNTIME_LIB"
}

_draccus_shell_rejects_piped_stdin() {
  local output status
  set +e
  output="$(printf 'echo DRACCUS_PIPE_TEST\n' | "$DRACCUS_BUNDLE/bin/draccus" shell 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] \
    && [[ "$output" != *DRACCUS_PIPE_TEST* ]] \
    && [[ "$output" == *"draccus shell is interactive-only"* ]] \
    && [[ "$output" == *"draccus run"* ]]
}

_draccus_shell_applies_project_context() {
  local tmpdir project subdir selected_bundle quoted_cmd ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-shell-project-context.XXXXXX")"
  project="$tmpdir/project"
  subdir="$project/nested/path"
  selected_bundle="$tmpdir/selected-bundle"
  mkdir -p \
    "$subdir" \
    "$selected_bundle/scripts" \
    "$selected_bundle/cache/starship/bin" \
    "$selected_bundle/rootfs/bin" \
    "$tmpdir/bin"
  touch "$selected_bundle/rootfs/bin/sh"
  cat >"$project/draccus.yaml" <<EOF
name: shell-project-context
bundle: $selected_bundle
EOF

  cat >"$selected_bundle/scripts/starship-version.env" <<'EOF'
STARSHIP_VERSION=v0.0.0
STARSHIP_URL=https://invalid.local/starship.tar.gz
STARSHIP_SHA256=0000000000000000000000000000000000000000000000000000000000000000
EOF
  cat >"$selected_bundle/cache/starship/bin/starship" <<'EOF'
#!/usr/bin/env bash
echo "starship 0.0.0"
EOF
  chmod +x "$selected_bundle/cache/starship/bin/starship"

  cat >"$tmpdir/bin/fake-bwrap" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$FAKE_BWRAP_LOG"
exit 0
EOF
  chmod +x "$tmpdir/bin/fake-bwrap"

  quoted_cmd="$(
    printf 'cd %q && BWRAP=%q FAKE_BWRAP_LOG=%q %q shell' \
      "$subdir" \
      "$tmpdir/bin/fake-bwrap" \
      "$tmpdir/bwrap.log" \
      "$DRACCUS_BUNDLE/bin/draccus"
  )"

  if script -q -e -c "$quoted_cmd" /dev/null >/dev/null 2>&1; then
    if grep -qF -- "--ro-bind $selected_bundle/rootfs /" "$tmpdir/bwrap.log" \
      && grep -qF -- "--bind $project /workspace" "$tmpdir/bwrap.log"; then
      ok=0
    fi
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_project_command_rejects_missing_config_bundle() {
  local command="$1"
  shift
  local tmpdir output status ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-project-bundle.XXXXXX")"

  cat >"$tmpdir/draccus.yaml" <<'EOF'
name: bundle-override-smoke
bundle: /definitely/missing/draccus-bundle
EOF

  set +e
  output="$(cd "$tmpdir" && "$DRACCUS_BUNDLE/bin/draccus" "$command" "$@" 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]] \
    && [[ "$output" == *"selected project bundle does not exist"* ]] \
    && [[ "$output" == *"/definitely/missing/draccus-bundle"* ]]; then
    ok=0
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_run_rejects_missing_config() {
  local tmpdir output status ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-cli-run-missing-config.XXXXXX")"

  set +e
  output="$(cd "$tmpdir" && "$DRACCUS_BUNDLE/bin/draccus" run --no-record -- true 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]] && [[ "$output" == *"no draccus.yaml found"* ]]; then
    ok=0
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_run_no_record_ok() {
  local tmpdir project output status ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-cli-run-no-record.XXXXXX")"
  project="$tmpdir/project"
  mkdir -p "$project"
  cat >"$project/draccus.yaml" <<EOF
name: run-no-record
runs_dir: records
EOF

  set +e
  output="$(cd "$project" && "$DRACCUS_BUNDLE/bin/draccus" run --no-record -- bash -lc 'echo no-record' 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]] \
    && [[ "$output" == *"no-record"* ]] \
    && [[ ! -e "$project/records" ]]; then
    ok=0
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_run_success_record_ok() {
  local tmpdir project output status run_json result_json ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-cli-run-success.XXXXXX")"
  project="$tmpdir/project"
  mkdir -p "$project"
  cat >"$project/draccus.yaml" <<EOF
name: run-success
runs_dir: records
EOF

  set +e
  output="$(cd "$project" && "$DRACCUS_BUNDLE/bin/draccus" run --name ok -- bash -lc 'echo out; echo err >&2' 2>&1)"
  status=$?
  set -e

  run_json="$(find "$project/records" -name run.json -print -quit 2>/dev/null || true)"
  result_json="$(find "$project/records" -name result.json -print -quit 2>/dev/null || true)"
  if [[ "$status" -eq 0 ]] \
    && [[ "$output" == *"out"* ]] \
    && [[ "$output" == *"err"* ]] \
    && [[ -n "$run_json" ]] \
    && [[ -n "$result_json" ]] \
    && python3 -m json.tool "$run_json" >/dev/null \
    && python3 -m json.tool "$result_json" >/dev/null \
    && grep -qF '"exit_code": 0' "$result_json" \
    && grep -qF 'out' "$(dirname "$run_json")/logs/stdout.log" \
    && grep -qF 'err' "$(dirname "$run_json")/logs/stderr.log"; then
    ok=0
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_run_failure_record_ok() {
  local tmpdir project output status run_json result_json ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-cli-run-failure.XXXXXX")"
  project="$tmpdir/project"
  mkdir -p "$project"
  cat >"$project/draccus.yaml" <<EOF
name: run-failure
EOF

  set +e
  output="$(cd "$project" && "$DRACCUS_BUNDLE/bin/draccus" run --name fail --runs-dir custom-runs -- bash -lc 'echo before-fail; exit 7' 2>&1)"
  status=$?
  set -e

  run_json="$(find "$project/custom-runs" -name run.json -print -quit 2>/dev/null || true)"
  result_json="$(find "$project/custom-runs" -name result.json -print -quit 2>/dev/null || true)"
  if [[ "$status" -eq 7 ]] \
    && [[ "$output" == *"before-fail"* ]] \
    && [[ -n "$run_json" ]] \
    && [[ -n "$result_json" ]] \
    && python3 -m json.tool "$run_json" >/dev/null \
    && python3 -m json.tool "$result_json" >/dev/null \
    && grep -qF '"exit_code": 7' "$result_json"; then
    ok=0
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_run_parallel_same_name_records_ok() {
  local tmpdir project expected=8 i status=0 run_json result_json ok=1
  local -a pids=() run_jsons=() result_jsons=()
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-cli-run-parallel.XXXXXX")"
  project="$tmpdir/project"
  mkdir -p "$project" "$tmpdir/bin" "$tmpdir/rootfs/bin"
  touch "$tmpdir/rootfs/bin/sh"
  cat >"$project/draccus.yaml" <<EOF
name: run-parallel
runs_dir: records
EOF

  cat >"$tmpdir/bin/fake-bwrap" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--chdir" ]]; then
    shift 2
    exec "$@"
  fi
  shift
done
echo "fake-bwrap: missing --chdir" >&2
exit 2
EOF
  chmod +x "$tmpdir/bin/fake-bwrap"

  cat >"$tmpdir/bin/date" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "-u +%Y%m%dT%H%M%SZ")
    echo "20300101T000000Z"
    ;;
  "-u +%Y-%m-%dT%H:%M:%SZ")
    echo "2030-01-01T00:00:00Z"
    ;;
  *)
    /usr/bin/date "$@"
    ;;
esac
EOF
  chmod +x "$tmpdir/bin/date"

  cat >"$tmpdir/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    */records/*/logs)
      sleep 0.2
      break
      ;;
  esac
done
exec /usr/bin/mkdir "$@"
EOF
  chmod +x "$tmpdir/bin/mkdir"

  for i in $(seq 1 "$expected"); do
    (
      cd "$project"
      PATH="$tmpdir/bin:$PATH" \
        BWRAP="$tmpdir/bin/fake-bwrap" \
        DRACCUS_ROOTFS="$tmpdir/rootfs" \
        DRACCUS_STATE="$tmpdir/state" \
        DRACCUS_CACHE="$tmpdir/cache" \
        DRACCUS_BUILD="$tmpdir/build" \
        "$DRACCUS_BUNDLE/bin/draccus" run --name same-name -- \
        bash -lc "echo stdout-marker-$i; echo stderr-marker-$i >&2"
    ) >"$tmpdir/run-$i.out" 2>&1 &
    pids+=("$!")
  done

  for i in "${pids[@]}"; do
    if ! wait "$i"; then
      status=1
    fi
  done

  mapfile -t run_jsons < <(find "$project/records" -name run.json -print 2>/dev/null | sort)
  mapfile -t result_jsons < <(find "$project/records" -name result.json -print 2>/dev/null | sort)
  if [[ "$status" -eq 0 ]] \
    && [[ "${#run_jsons[@]}" -eq "$expected" ]] \
    && [[ "${#result_jsons[@]}" -eq "$expected" ]]; then
    ok=0
    for run_json in "${run_jsons[@]}"; do
      result_json="$(dirname "$run_json")/result.json"
      if ! python3 -m json.tool "$run_json" >/dev/null \
        || ! python3 -m json.tool "$result_json" >/dev/null \
        || ! grep -qF '"exit_code": 0' "$result_json" \
        || [[ ! -s "$(dirname "$run_json")/logs/stdout.log" ]] \
        || [[ ! -s "$(dirname "$run_json")/logs/stderr.log" ]]; then
        ok=1
      fi
    done
    for i in $(seq 1 "$expected"); do
      if ! grep -R -qF "stdout-marker-$i" "$project/records" \
        || ! grep -R -qF "stderr-marker-$i" "$project/records"; then
        ok=1
      fi
    done
  fi

  rm -rf "$tmpdir"
  return "$ok"
}

_draccus_uv_explicit_pip_target_does_not_auto_target_workspace() {
  local tmpdir project calls ok=1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-uv-explicit-target.XXXXXX")"
  project="$tmpdir/project"
  mkdir -p "$project/.venv/bin" "$tmpdir/bin" "$tmpdir/rootfs/bin"
  touch "$project/.venv/pyvenv.cfg" "$tmpdir/rootfs/bin/sh"
  cat >"$project/draccus.yaml" <<'EOF'
name: uv-explicit-target
EOF

  cat >"$tmpdir/bin/fake-bwrap" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--chdir" ]]; then
    shift 2
    exec "$@"
  fi
  shift
done
echo "fake-bwrap: missing --chdir" >&2
exit 2
EOF
  chmod +x "$tmpdir/bin/fake-bwrap"

  cat >"$tmpdir/bin/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_UV_LOG"
EOF
  chmod +x "$tmpdir/bin/uv"

  if (
    cd "$project"
    PATH="$tmpdir/bin:$PATH" \
      BWRAP="$tmpdir/bin/fake-bwrap" \
      FAKE_UV_LOG="$tmpdir/uv.log" \
      DRACCUS_ROOTFS="$tmpdir/rootfs" \
      DRACCUS_STATE="$tmpdir/state" \
      DRACCUS_CACHE="$tmpdir/cache" \
      DRACCUS_BUILD="$tmpdir/build" \
      "$DRACCUS_BUNDLE/bin/draccus" uv pip install --python /tmp/custom-python okpkg
  ); then
    calls="$(wc -l <"$tmpdir/uv.log")"
    if [[ "$calls" -eq 2 ]] \
      && grep -qF 'pip install --dry-run --python /tmp/custom-python okpkg' "$tmpdir/uv.log" \
      && grep -qF 'pip install --python /tmp/custom-python okpkg' "$tmpdir/uv.log" \
      && ! grep -qF '/workspace/.venv/bin/python' "$tmpdir/uv.log"; then
      ok=0
    fi
  fi

  rm -rf "$tmpdir"
  return "$ok"
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
  "$DRACCUS_BUNDLE/bin/draccus"
  "$DRACCUS_BUNDLE/host-bin/nvidia-smi"
  "$DRACCUS_BUNDLE/lib/draccus-cli.sh"
  "$DRACCUS_BUNDLE/lib/draccus-doctor.sh"
  "$DRACCUS_BUNDLE/lib/draccus-layout.sh"
  "$DRACCUS_BUNDLE/lib/draccus-notebook.sh"
  "$DRACCUS_BUNDLE/lib/draccus-project.sh"
  "$DRACCUS_BUNDLE/lib/draccus-run-record.sh"
  "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"
  "$DRACCUS_BUNDLE/lib/draccus-shell.sh"
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

check "no legacy public entrypoints" "_draccus_no_legacy_public_entrypoints"
check "executable: draccus" "test -x \"$DRACCUS_BUNDLE/bin/draccus\""
check "draccus respects DRACCUS_BUNDLE override" "_draccus_cli_respects_bundle_env"

echo ""

# ============================================================================
# CHECK 8B - draccus command help
# ============================================================================

echo "=== CHECK 8B: draccus command help ==="

check "draccus --help mentions draccus shell" "\"$DRACCUS_BUNDLE/bin/draccus\" --help | grep -qF 'draccus shell'"
check "draccus --help mentions draccus run" "\"$DRACCUS_BUNDLE/bin/draccus\" --help | grep -qF 'draccus run'"
check "draccus run help documents --runs-dir" "\"$DRACCUS_BUNDLE/bin/draccus\" help run | grep -qF 'Relative --runs-dir values are resolved from the project root'"
check "draccus run rejects missing draccus.yaml" "_draccus_run_rejects_missing_config"
check "draccus run applies project bundle before runtime" "_draccus_project_command_rejects_missing_config_bundle run --no-record -- true"
check "draccus run --no-record creates no run directory" "_draccus_run_no_record_ok"
check "draccus run writes successful JSON record and logs" "_draccus_run_success_record_ok"
check "draccus run preserves failure exit code and record" "_draccus_run_failure_record_ok"
check "draccus run allocates same-name parallel records atomically" "_draccus_run_parallel_same_name_records_ok"
check "draccus shell rejects piped stdin" "_draccus_shell_rejects_piped_stdin"
check "draccus shell applies project bundle and workspace context" "_draccus_shell_applies_project_context"
check "draccus uv applies project bundle before runtime" "_draccus_project_command_rejects_missing_config_bundle uv --version"
check "draccus notebook applies project bundle before runtime" "_draccus_project_command_rejects_missing_config_bundle notebook --port 9999"

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
check "shims/pip directs users to draccus uv pip" "grep -Fq 'draccus uv pip <args>' \"$DRACCUS_BUNDLE/shims/pip\" && grep -Fq 'draccus uv pip <args>' \"$DRACCUS_BUNDLE/shims/pip3\""
check "active docs/config have no legacy public command refs" "_draccus_no_stale_active_public_refs"
check "pre-commit shell hooks include bin/draccus" "grep -Fq 'bin/draccus$' \"$DRACCUS_BUNDLE/.pre-commit-config.yaml\""
check "pre-commit shell hooks do not target legacy draccus wildcard" "! grep -Fq 'bin/draccus-' \"$DRACCUS_BUNDLE/.pre-commit-config.yaml\""
check "mise project tasks document explicit project selection" "grep -Fq 'DRACCUS_PROJECT' \"$DRACCUS_BUNDLE/mise.toml\" && grep -Fq 'draccus.yaml' \"$DRACCUS_BUNDLE/mise.toml\""
check "mise validate avoids unmounted /opt/draccus scripts" "! grep -Fq '/opt/draccus/scripts/validate_foundation.py' \"$DRACCUS_BUNDLE/mise.toml\""
check "validate-all calls the defined mise validation task" "! grep -Fq 'mise run draccus-validate' \"$DRACCUS_BUNDLE/scripts/validate-all.sh\""
DRACCUS_RUNTIME_LIB="$DRACCUS_BUNDLE/lib/draccus-runtime.sh"
DRACCUS_LAYOUT_LIB="$DRACCUS_BUNDLE/lib/draccus-layout.sh"
DRACCUS_PROJECT_LIB="$DRACCUS_BUNDLE/lib/draccus-project.sh"
check "draccus-runtime library exists" "test -f \"$DRACCUS_RUNTIME_LIB\""
check "draccus-layout library exists" "test -f \"$DRACCUS_LAYOUT_LIB\""
check "draccus-layout exposes shared roots" "grep -qF 'draccus_managed_projects_root()' \"$DRACCUS_LAYOUT_LIB\""
check "draccus-layout exposes slug helper" "grep -qF 'draccus_slug()' \"$DRACCUS_LAYOUT_LIB\""
check "draccus-project discovers draccus.yaml" "grep -qF 'draccus_project_config_path()' \"$DRACCUS_PROJECT_LIB\""
check "draccus-project parses yaml values" "grep -qF 'draccus_yaml_value()' \"$DRACCUS_PROJECT_LIB\""
check "draccus-project reports missing config guidance" "grep -qF 'draccus: error: no draccus.yaml found. Run: draccus project init <name>' \"$DRACCUS_PROJECT_LIB\""
check "draccus-project validates parsed DO_NOT_SHADOW sentinels" "grep -qF 'failed to parse DO_NOT_SHADOW' \"$DRACCUS_PROJECT_LIB\" && grep -qF 'missing sentinel' \"$DRACCUS_PROJECT_LIB\""
check "draccus-project refuses mismatched existing config name" "grep -qF 'existing draccus.yaml has name' \"$DRACCUS_PROJECT_LIB\""
check "draccus-project preserves existing pyproject metadata" "grep -qF 'created_pyproject=1' \"$DRACCUS_PROJECT_LIB\" && grep -qF 'update_pyproject=\"\$1\"' \"$DRACCUS_PROJECT_LIB\""
check "draccus CLI dispatches build through runtime library" "grep -qF 'draccus_runtime_exec_build \"\$@\"' \"$DRACCUS_BUNDLE/lib/draccus-cli.sh\""
check "draccus CLI dispatches run through run-record library" "grep -qF 'draccus_run_main \"\$@\"' \"$DRACCUS_BUNDLE/lib/draccus-cli.sh\""
check "draccus-run-record library exists" "test -f \"$DRACCUS_BUNDLE/lib/draccus-run-record.sh\""
check "runtime run mode ro-binds bundle shims to /opt/draccus/shims" "_draccus_run_binds_shims"
check "runtime run mode ro-binds host-bin to /opt/draccus/host-bin" "grep -qF -- '--ro-bind \"\$DRACCUS_BUNDLE/host-bin\" /opt/draccus/host-bin' \"$DRACCUS_RUNTIME_LIB\""
check "runtime run mode PATH leads with /opt/draccus/shims" "grep -qF 'draccus_path_views=\"/opt/draccus/shims:' \"$DRACCUS_RUNTIME_LIB\""
check "runtime run mode PATH includes host-bin" "grep -qF '/opt/draccus/host-bin' \"$DRACCUS_RUNTIME_LIB\""
check "runtime run mode PATH includes spack bin" "grep -qF '/opt/draccus/spack/bin' \"$DRACCUS_RUNTIME_LIB\""
check "runtime run mode PATH includes starship cache bin" "grep -qF '/opt/draccus/cache/starship/bin' \"$DRACCUS_RUNTIME_LIB\""
check "draccus shell sources Spack setup" "grep -qF '/opt/draccus/spack/share/spack/setup-env.sh' \"$DRACCUS_BUNDLE/lib/draccus-shell.sh\""
check "runtime run mode disables Spack locks for readonly inspection" "grep -qF 'SPACK_USER_CONFIG_PATH /opt/draccus/cache/spack-readonly-config' \"$DRACCUS_RUNTIME_LIB\""
check "runtime run mode mirrors Spack env metadata for readonly activation" "grep -qF 'spack-readonly-envs' \"$DRACCUS_RUNTIME_LIB\""
check "draccus shell rewrites managed env activation to readonly mirror" "grep -qF '_draccus_spack_upstream' \"$DRACCUS_BUNDLE/lib/draccus-shell.sh\""
check "draccus shell launches zsh" "grep -qF 'zsh' \"$DRACCUS_BUNDLE/lib/draccus-shell.sh\""
check "draccus shell configures starship" "grep -qF 'starship init zsh' \"$DRACCUS_BUNDLE/lib/draccus-shell.sh\""
check "starship-version.env exists" "test -f \"$DRACCUS_BUNDLE/scripts/starship-version.env\""
check "runtime run mode exports base-ml PYTHONPATH" "grep -qF '/opt/draccus/view/base-ml/lib/python3.12/site-packages' \"$DRACCUS_RUNTIME_LIB\""
check "runtime has no host_uv / DRACCUS_HOST_UV_BIN" "! grep -qE 'DRACCUS_HOST_UV_BIN|host_uv_' \"$DRACCUS_RUNTIME_LIB\""
check "host-bin/nvidia-smi fallback executable" "test -x \"$DRACCUS_BUNDLE/host-bin/nvidia-smi\""
check "draccus CLI dispatches uv through uv library" "grep -qF 'draccus_uv_main \"\$@\"' \"$DRACCUS_BUNDLE/lib/draccus-cli.sh\""
check "draccus uv auto-targets workspace .venv for pip installs" "grep -qF -- '--python /workspace/.venv/bin/python' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""
check "draccus uv blocks direct foundation package installs" "grep -qF 'refusing to install foundation package' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""
check "draccus uv audits resolved install plans" "grep -qF -- '--dry-run' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""
check "draccus uv explicit pip target does not also target workspace venv" "_draccus_uv_explicit_pip_target_does_not_auto_target_workspace"

echo ""

# ============================================================================
# CHECK 10 - Gate 0 runtime-boundary guard
# ============================================================================

echo "=== CHECK 10: Gate 0 runtime-boundary guard ==="

check "Gate 0 does not run draccus doctor" "! grep -v 'Gate 0 does not run' \"$DRACCUS_BUNDLE/scripts/validate-static.sh\" | grep -qF '\"$DRACCUS_BUNDLE/bin/draccus\" doctor'"

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
