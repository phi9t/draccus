#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

"$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh
  spack env activate -p base-sys

  echo "[base-sys paths]"
  test "$SPACK_ROOT" = /opt/draccus/spack
  which gcc g++ gfortran clang clang++ lld cmake ninja git tmux zsh rg eza dust fd jq

  echo "[base-sys versions]"
  gcc --version | head -1
  clang --version | head -1
  cmake --version | head -1
  ninja --version | head -1
  git --version | head -1

  echo "[base-sys no-cuda check]"
  if command -v nvcc >/dev/null 2>&1; then
    echo "WARNING: nvcc found in base-sys (unexpected)"
  else
    echo "OK: no nvcc in base-sys"
  fi

  echo "base-sys validation OK"
'
