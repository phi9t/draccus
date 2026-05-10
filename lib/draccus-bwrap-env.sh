#!/usr/bin/env bash
# Resolve CUDA toolchain paths for Bubblewrap launchers on the HOST before exec.
#
# Prefer the Spack base-ml unified view whenever it exposes nvcc; otherwise fall back to
# the CUDA toolkit pinned in rootfs (/usr/local/cuda-* mirrors the NVIDIA CUDA image layout).

: "${DRACCUS_STATE:?DRACCUS_STATE must be set before sourcing draccus-bwrap-env.sh}"
: "${DRACCUS_ROOTFS:?DRACCUS_ROOTFS must be set before sourcing draccus-bwrap-env.sh}"

shopt -s nocasematch

if [[ ! "${DRACCUS_USE_DOCKER_CUDA:-1}" =~ ^(0|false|no)$ ]]; then
  if [[ -x "${DRACCUS_STATE}/view/base-ml/bin/nvcc" ]]; then
    DRACCUS_RESOLVED_CUDA_HOME="/opt/draccus/view/base-ml"
    DRACCUS_RESOLVED_CUDA_ROOT="/opt/draccus/view/base-ml"
  else
    DRACCUS_RESOLVED_CUDA_HOME="${DRACCUS_DOCKER_CUDA_HOME:-/usr/local/cuda}"
    DRACCUS_RESOLVED_CUDA_ROOT="${DRACCUS_DOCKER_CUDA_ROOT:-${DRACCUS_DOCKER_CUDA_HOME:-/usr/local/cuda}}"
  fi
else
  DRACCUS_RESOLVED_CUDA_HOME="/opt/draccus/view/base-ml"
  DRACCUS_RESOLVED_CUDA_ROOT="/opt/draccus/view/base-ml"
fi

DRACCUS_BWRAP_CUDA_BIN_PREFIX=""
DRACCUS_BWRAP_CUDA_LD_EXTRA=""
ROOTFS_CANON="${DRACCUS_ROOTFS%/}"

shopt -s nullglob

_nvcc_paths=("${ROOTFS_CANON}"/usr/local/cuda-*/bin/nvcc)
[[ -x "${ROOTFS_CANON}/usr/local/cuda/bin/nvcc" ]] && _nvcc_paths+=("${ROOTFS_CANON}/usr/local/cuda/bin/nvcc")

for nvcc_host in "${_nvcc_paths[@]}"; do
  [[ -x "$nvcc_host" ]] || continue

  inner_nvcc="${nvcc_host#"${ROOTFS_CANON}"}"
  inner_nvcc="${inner_nvcc#/}"

  cuda_bin_dir="${inner_nvcc%/*}"
  cuda_home="${cuda_bin_dir%/*}"

  DRACCUS_BWRAP_CUDA_BIN_PREFIX="/${cuda_bin_dir}:${DRACCUS_BWRAP_CUDA_BIN_PREFIX}"

  lib_dir_inner="/${cuda_home}/lib64"
  if [[ -d "${ROOTFS_CANON}${lib_dir_inner}" ]]; then
    DRACCUS_BWRAP_CUDA_LD_EXTRA="${lib_dir_inner#/}:${DRACCUS_BWRAP_CUDA_LD_EXTRA}"
  fi
done

shopt -u nullglob

if [[ -z "${DRACCUS_BWRAP_CUDA_BIN_PREFIX:-}" ]]; then
  DRACCUS_BWRAP_CUDA_BIN_PREFIX="/usr/local/cuda/bin:"
else
  DRACCUS_BWRAP_CUDA_BIN_PREFIX="${DRACCUS_BWRAP_CUDA_BIN_PREFIX%:}:"
fi

if [[ -z "${DRACCUS_BWRAP_CUDA_LD_EXTRA:-}" ]]; then
  DRACCUS_BWRAP_CUDA_LD_EXTRA="/usr/local/cuda/lib64:"
else
  DRACCUS_BWRAP_CUDA_LD_EXTRA="${DRACCUS_BWRAP_CUDA_LD_EXTRA%:}:"
fi

shopt -u nocasematch
