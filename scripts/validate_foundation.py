#!/usr/bin/env python3
"""Draccus foundation validation (EDD Appendix B / Gates 6–9).

Expects to run inside draccus-run with base-ml activated:

  . /opt/draccus/spack/share/spack/setup-env.sh && spack env activate -p base-ml
"""

from __future__ import annotations

import os
import subprocess
import sys


def _foundation_path_ok(path: str | None) -> bool:
    return bool(path) and "/opt/draccus/" in path


def main() -> int:
    if os.environ.get("SPACK_ROOT") != "/opt/draccus/spack":
        print("validate_foundation: SPACK_ROOT must be /opt/draccus/spack", file=sys.stderr)
        return 1
    cuda_home = os.environ.get("CUDA_HOME")
    if cuda_home not in {"/opt/draccus/view/base-ml", "/usr/local/cuda"}:
        print(
            f"validate_foundation: CUDA_HOME must be canonical (/opt/draccus/view/base-ml "
            f"once base-ml view exists or /usr/local/cuda Docker rootfs), got {cuda_home!r}",
            file=sys.stderr,
        )
        return 1

    import torch

    print("torch", torch.__version__, torch.__file__)
    print("cuda", torch.version.cuda)
    print("available", torch.cuda.is_available())
    print("count", torch.cuda.device_count())
    if not _foundation_path_ok(torch.__file__):
        print("validate_foundation: torch not under /opt/draccus", file=sys.stderr)
        return 1
    if not torch.cuda.is_available() or torch.cuda.device_count() < 1:
        print("validate_foundation: CUDA not available or no GPUs", file=sys.stderr)
        return 1
    for i in range(torch.cuda.device_count()):
        p = torch.cuda.get_device_properties(i)
        print(i, p.name, p.major, p.minor)
        if p.major != 10:
            msg = f"validate_foundation: expected SM major 10 (B200), got {p.major}"
            print(msg, file=sys.stderr)
            return 1
    x = torch.randn((2048, 2048), device="cuda", dtype=torch.float16)
    y = x @ x
    torch.cuda.synchronize()
    print("torch ok", y.shape)

    import jax
    import jax.numpy as jnp

    print("jax", jax.__version__)
    print(jax.devices())
    jax_path = getattr(jax, "__file__", "") or ""
    if not _foundation_path_ok(jax_path):
        print("validate_foundation: jax not under /opt/draccus", file=sys.stderr)
        return 1
    try:
        import jaxlib as jaxlib_mod
    except ImportError:
        jaxlib_mod = None
    if jaxlib_mod is not None:
        jx = getattr(jaxlib_mod, "__file__", "") or ""
        if not _foundation_path_ok(jx):
            print("validate_foundation: jaxlib not under /opt/draccus", file=sys.stderr)
            return 1
    if not [d for d in jax.devices() if d.platform == "gpu"]:
        print("validate_foundation: no JAX GPU devices", file=sys.stderr)
        return 1
    a = jnp.ones((1024, 1024), dtype=jnp.float16)
    b = a @ a
    print("jax ok", b.shape)

    import numpy as np
    import scipy

    print(np.__version__, np.__file__)
    print(scipy.__version__, scipy.__file__)
    if not _foundation_path_ok(np.__file__):
        print("validate_foundation: numpy not under /opt/draccus", file=sys.stderr)
        return 1
    if not _foundation_path_ok(scipy.__file__):
        print("validate_foundation: scipy not under /opt/draccus", file=sys.stderr)
        return 1

    try:
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-version"],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
        print("validate_foundation: ffmpeg check failed:", e, file=sys.stderr)
        return 1

    print("foundation validation OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
