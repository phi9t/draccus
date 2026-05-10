#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

"$DRACCUS_BUNDLE/bin/draccus-run" bash -lc '
  set -euo pipefail
  . /opt/draccus/spack/share/spack/setup-env.sh
  spack env activate -p base-ml

  echo "[paths]"
  test "$SPACK_ROOT" = /opt/draccus/spack
  case "$CUDA_HOME" in
    /opt/draccus/view/base-ml | /usr/local/cuda ) ;;
    *)
      printf 'ERROR: CUDA_HOME=%s expected /opt/draccus/view/base-ml or /usr/local/cuda\\n' "$CUDA_HOME" >&2
      exit 1 ;;
  esac
  which python
  which nvcc
  which ffmpeg

  echo "[torch]"
  python - <<PY
import torch
print("torch", torch.__version__, torch.__file__)
print("cuda", torch.version.cuda)
print("available", torch.cuda.is_available())
print("count", torch.cuda.device_count())
assert "/opt/draccus/" in torch.__file__, torch.__file__
assert torch.cuda.is_available()
assert torch.cuda.device_count() >= 1
for i in range(torch.cuda.device_count()):
    p = torch.cuda.get_device_properties(i)
    print(i, p.name, p.major, p.minor)
    assert p.major == 10
x = torch.randn((2048, 2048), device="cuda", dtype=torch.float16)
y = x @ x
torch.cuda.synchronize()
print("torch ok", y.shape)
PY

  echo "[jax]"
  python - <<PY
import jax
import jax.numpy as jnp
print("jax", jax.__version__, jax.__file__)
print(jax.devices())
assert "/opt/draccus/" in jax.__file__, jax.__file__
import jaxlib
assert "/opt/draccus/" in jaxlib.__file__, jaxlib.__file__
assert [d for d in jax.devices() if d.platform == "gpu"]
x = jnp.ones((1024, 1024), dtype=jnp.float16)
y = x @ x
print("jax ok", y.shape)
PY

  echo "[numpy/scipy]"
  python - <<PY
import numpy, scipy
print(numpy.__version__, numpy.__file__)
print(scipy.__version__, scipy.__file__)
assert "/opt/draccus/" in numpy.__file__
assert "/opt/draccus/" in scipy.__file__
PY

  echo "[ffmpeg]"
  ffmpeg -hide_banner -version | head -20
  ffmpeg -hide_banner -encoders | grep -E "libx264|libx265|libvpx|libaom|nvenc" || true

  echo "base-ml validation OK"
'
