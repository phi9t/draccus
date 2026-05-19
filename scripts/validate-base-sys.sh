#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

# Gate 3: exercise the runtime contract (draccus-run mounts Spack read-only).
# Avoid `spack env activate` here — Spack tries to acquire a transaction lock under the
# environment directory and fails with EROFS under draccus-run.
"$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
  set -euo pipefail

  echo "[base-sys paths]"
  test "${SPACK_ROOT:-}" = /opt/draccus/spack
  which gcc g++ clang clang++ lld cmake ninja git tmux zsh rg eza dust fd jq
  if command -v gfortran >/dev/null 2>&1; then
    : # Ubuntu meta-package may expose gfortran
  else
    command -v gfortran-13
  fi

  echo "[base-sys versions]"
  gcc --version | head -1
  clang --version | head -1
  cmake --version | head -1
  ninja --version | head -1
  git --version | head -1

  echo "[base-sys no-cuda check]"
  nv="$(command -v nvcc || true)"
  case "${nv:-}" in
    "")
      echo "OK: nvcc not on PATH"
      ;;
    /opt/draccus/view/* | /opt/draccus/spack/*)
      echo "ERROR: nvcc resolves from Draccus Spack/views in base-sys (unexpected): $nv" >&2
      exit 1
      ;;
    *)
      echo "OK: nvcc on PATH at $nv (host/CUDA mounts only; base-sys specs have no CUDA)"
      ;;
  esac

  echo "base-sys validation OK"
'
