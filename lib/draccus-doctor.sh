# shellcheck shell=bash
# Draccus user-facing health checks.
# Source this file; do not execute directly.

# shellcheck source=draccus-layout.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-layout.sh"
# shellcheck source=draccus-runtime.sh
source "${DRACCUS_CLI_ROOT:-$DRACCUS_BUNDLE}/lib/draccus-runtime.sh"

draccus_doctor_emit_json() {
  local ok="$1"
  local bundle="$2"
  local error="${3:-}"
  local guidance="${4:-}"

  if [[ -n "$error" && -n "$guidance" ]]; then
    printf '{"ok":%s,"bundle":%s,"error":%s,"guidance":%s}\n' \
      "$ok" \
      "$(draccus_json_string "$bundle")" \
      "$(draccus_json_string "$error")" \
      "$(draccus_json_string "$guidance")"
  elif [[ -n "$error" ]]; then
    printf '{"ok":%s,"bundle":%s,"error":%s}\n' \
      "$ok" \
      "$(draccus_json_string "$bundle")" \
      "$(draccus_json_string "$error")"
  else
    printf '{"ok":%s,"bundle":%s}\n' \
      "$ok" \
      "$(draccus_json_string "$bundle")"
  fi
}

draccus_doctor_fail() {
  local json="$1"
  local bundle="$2"
  local error="$3"
  local guidance="${4:-}"

  if [[ "$json" -eq 1 ]]; then
    draccus_doctor_emit_json false "$bundle" "$error" "$guidance"
  else
    echo "draccus doctor: $error" >&2
    if [[ -n "$guidance" ]]; then
      echo "$guidance" >&2
    fi
  fi
}

draccus_doctor_main() {
  local json=0
  local bundle="${DRACCUS_BUNDLE:-$(draccus_default_bundle)}"
  local rootfs="${DRACCUS_ROOTFS:-$bundle/rootfs}"
  local runtime_rc=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      *)
        draccus_doctor_fail "$json" "$bundle" "unknown argument '$1'"
        return 2
        ;;
    esac
  done

  if [[ ! -d "$bundle" || ! -e "$rootfs/bin/sh" ]]; then
    draccus_doctor_fail "$json" "$bundle" "selected bundle is missing or incomplete: $bundle" \
      "Bootstrap a bundle first or set DRACCUS_BUNDLE to an existing Draccus checkout/bundle."
    return 1
  fi

  if ! compgen -G "/dev/nvidia*" >/dev/null; then
    draccus_doctor_fail "$json" "$bundle" "no /dev/nvidia* devices visible; B200 training requires GPUs"
    return 1
  fi

  (
    DRACCUS_ROOTFS="$rootfs" draccus_runtime_exec_run bash -lc '
      set -euo pipefail
      test "${DRACCUS_PREFIX:-}" = /opt/draccus
      test "${SPACK_ROOT:-}" = /opt/draccus/spack
      test "$(command -v uv)" = /usr/local/bin/uv
      test "$(command -v pip)" = /opt/draccus/shims/pip
      python - <<'"'"'PY'"'"'
import jax
import jaxlib
import numpy
import scipy
import torch

for module in (torch, jax, jaxlib, numpy, scipy):
    path = getattr(module, "__file__", "")
    if not path.startswith("/opt/draccus/"):
        raise AssertionError(f"{module.__name__} resolved outside /opt/draccus: {path}")
PY
    '
  ) || runtime_rc=$?

  if [[ "$runtime_rc" -ne 0 ]]; then
    draccus_doctor_fail "$json" "$bundle" "runtime checks failed"
    return "$runtime_rc"
  fi

  if [[ "$json" -eq 1 ]]; then
    draccus_doctor_emit_json true "$bundle"
  else
    echo "draccus doctor: OK"
  fi
}
