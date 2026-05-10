#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

"$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh
  spack env activate -p base-ml

  if [[ ! -d /work/src/.venv ]]; then
    echo "Creating project venv..."
    uv venv --python "$(which python)" --system-site-packages /work/src/.venv
  fi

  source /work/src/.venv/bin/activate

  echo "[overlay imports]"
  python - <<PY
import importlib
import sys

foundation = ["torch", "jax", "numpy", "scipy"]
project = ["transformers", "datasets", "accelerate"]

for name in foundation:
    mod = importlib.import_module(name)
    path = getattr(mod, "__file__", "")
    print(f"{name}: {path}")
    assert "/opt/draccus/" in path, f"{name} is not from Draccus: {path}"

for name in project:
    try:
        mod = importlib.import_module(name)
        path = getattr(mod, "__file__", "")
        print(f"{name}: {path}")
        assert "/work/src/.venv/" in path, f"{name} is not from project venv: {path}"
    except ImportError:
        print(f"{name}: not installed (optional)")

import torch
assert torch.cuda.is_available(), "torch CUDA unavailable"
print("project overlay validation OK")
PY
'
