#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"
# shellcheck source=../lib/draccus-project.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-project.sh"

"$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
  set -euo pipefail
  export PATH="/opt/draccus/view/base-ml/bin:${PATH}"
  export SPACK_ROOT=/opt/draccus/spack

  if [[ ! -d /workspace/.venv ]]; then
    echo "Creating project venv..."
    uv venv --python "$(which python)" --system-site-packages /workspace/.venv
  fi

  source /workspace/.venv/bin/activate
  # uv venv "system" site-packages follow the underlying Spack python@3.12 prefix, not the unified
  # base-ml Spack view — force the view site dir so torch/jax/etc. resolve from /opt/draccus.
  _ml_site=/opt/draccus/view/base-ml/lib/python3.12/site-packages
  export PYTHONPATH="${_ml_site}${PYTHONPATH:+:${PYTHONPATH}}"

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
        assert "/workspace/.venv/" in path, f"{name} is not from project venv: {path}"
    except ImportError:
        print(f"{name}: not installed (optional)")

import torch
assert torch.cuda.is_available(), "torch CUDA unavailable"
print("project overlay validation OK")
PY
'

draccus_project_neutralize_pip "${PWD%/}/.venv"
