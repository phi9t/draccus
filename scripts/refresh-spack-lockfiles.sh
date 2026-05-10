#!/usr/bin/env bash
# Regenerate mirrored Spack lockfiles under envs/*/spack.lock (EDD §8.1) using draccus-build.
# Requires: working Spack checkout under state/spack, network for solves as needed.
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

DRACCUS_RUN_BUILD="${DRACCUS_BUNDLE}/bin/draccus-build"

"${DRACCUS_RUN_BUILD}" bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh

  for env in base-sys base-ml; do
    echo "[refresh-lock] (${env})"
    spack env rm -y "$env" 2>/dev/null || true
    unset SPACK_ENV || true

    spack env create "$env" "/opt/draccus/envs/${env}/spack.yaml"

    spack -e "$env" concretize --force --fresh

    env_dir="$(spack location -e "$env")"
    if [[ ! -f "$env_dir/spack.lock" ]]; then
      echo "ERROR: Missing spack.lock under $env_dir" >&2
      exit 1
    fi

    install -m 0644 "$env_dir/spack.lock" "/opt/draccus/envs/${env}/spack.lock"
    ls -la "/opt/draccus/envs/${env}/spack.lock"
  done

  echo "[refresh-lock] done"
'
