#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"
# shellcheck source=../lib/draccus-runtime.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-runtime.sh"

draccus_runtime_exec_run bash -lc '
  set -euo pipefail

  echo "[paths]"
  test "${SPACK_ROOT:-}" = /opt/draccus/spack
  export PATH="/opt/draccus/view/base-ml/bin:${PATH}"
  # Spack jaxlib installs omit JAX pip `nvidia.*` shim dirs used for dlopen (`jax_plugins.xla_cuda12._load_nvidia_libraries`).
  # After installing `py-jaxlib`, run the one-time stub layout under the active workstream (`.workstream/spack-envs-bootstrap/artifacts/p4.3-jax-nvidia-stubs.sh` or tracker ** Log) inside `draccus build`.
  # PJRT CUDA optional `cufftGetVersion`/`cuSOLVER` probes can also spuriously fail on multi-toolkit Docker rootfs; skip version probes while keeping real GPU asserts below.
  export JAX_SKIP_CUDA_CONSTRAINTS_CHECK="${JAX_SKIP_CUDA_CONSTRAINTS_CHECK:-1}"

  case "${CUDA_HOME}" in
    /opt/draccus/view/base-ml | /usr/local/cuda ) ;;
    *)
      printf >&2 "ERROR: CUDA_HOME=%s expected /opt/draccus/view/base-ml or /usr/local/cuda\n" "${CUDA_HOME}"
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
