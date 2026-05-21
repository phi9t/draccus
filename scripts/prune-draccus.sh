#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

"$DRACCUS_BUNDLE/bin/draccus" build -- bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh
  echo "Unused specs:"
  spack find --unused || true
  echo "Running GC"
  spack gc -y
  echo "Cleaning build stages"
  spack clean -s
  echo "Cleaning misc cache"
  spack clean -m
'
