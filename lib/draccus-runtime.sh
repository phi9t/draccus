#!/usr/bin/env bash

# shellcheck source=draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-env.sh"

draccus_runtime_exec_run() {
  DRACCUS_RUNTIME_MODE=run draccus_runtime_exec "$@"
}

draccus_runtime_exec_build() {
  DRACCUS_RUNTIME_MODE=build draccus_runtime_exec "$@"
}

draccus_runtime_exec() {
  local runtime_mode="${DRACCUS_RUNTIME_MODE:-run}"
  local launcher_name

  case "$runtime_mode" in
    run | build)
      launcher_name="draccus-$runtime_mode"
      ;;
    *)
      echo "draccus-runtime: invalid runtime mode: $runtime_mode" >&2
      exit 2
      ;;
  esac

  DRACCUS_ROOTFS="${DRACCUS_ROOTFS:-$DRACCUS_BUNDLE/rootfs}"
  DRACCUS_STATE="${DRACCUS_STATE:-$DRACCUS_BUNDLE/state}"
  DRACCUS_CACHE="${DRACCUS_CACHE:-$DRACCUS_BUNDLE/cache}"
  DRACCUS_BUILD="${DRACCUS_BUILD:-$DRACCUS_BUNDLE/build}"
  DRACCUS_WORKSPACE="${DRACCUS_WORKSPACE:-$PWD}"

  # shellcheck source=draccus-bwrap-env.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-bwrap-env.sh"

  local cuda_ld_extra=""
  if [[ -n "${DRACCUS_BWRAP_CUDA_LD_EXTRA:-}" ]]; then
    cuda_ld_extra=":${DRACCUS_BWRAP_CUDA_LD_EXTRA%:}"
  fi

  local -a uv_overrides_args=()
  if [[ "$runtime_mode" == "run" && -f "$DRACCUS_BUNDLE/scripts/uv_overrides.txt" ]]; then
    uv_overrides_args+=(--ro-bind "$DRACCUS_BUNDLE/scripts/uv_overrides.txt" /opt/draccus/uv_overrides.txt)
    uv_overrides_args+=(--setenv UV_EXTRA_OVERRIDES /opt/draccus/uv_overrides.txt)
  fi

  BWRAP="${BWRAP:-$(command -v bwrap || true)}"

  if [[ -z "$BWRAP" || ! -x "$BWRAP" ]]; then
    echo "$launcher_name: bubblewrap (bwrap) not found; install bubblewrap" >&2
    exit 127
  fi

  if [[ ! -e "$DRACCUS_ROOTFS/bin/sh" ]]; then
    echo "$launcher_name: rootfs incomplete: missing $DRACCUS_ROOTFS/bin/sh (see EDD §11.2)" >&2
    exit 1
  fi

  mkdir -p \
    "$DRACCUS_STATE/spack" \
    "$DRACCUS_STATE/view" \
    "$DRACCUS_STATE/var-intel" \
    "$DRACCUS_CACHE/spack" \
    "$DRACCUS_CACHE/uv" \
    "$DRACCUS_CACHE/huggingface" \
    "$DRACCUS_BUILD/stage"

  if [[ "$runtime_mode" == "run" ]]; then
    mkdir -p \
      "$DRACCUS_CACHE/spack-readonly-config" \
      "$DRACCUS_CACHE/spack-readonly-envs"

    cat >"$DRACCUS_CACHE/spack-readonly-config/config.yaml" <<'EOF'
config:
  locks: false
EOF

    if [[ -d "$DRACCUS_STATE/spack/var/spack/environments" ]]; then
      local draccus_env_dir
      for draccus_env_dir in "$DRACCUS_STATE/spack/var/spack/environments"/*; do
        [[ -d "$draccus_env_dir" ]] || continue
        local draccus_env_name
        draccus_env_name="$(basename "$draccus_env_dir")"
        mkdir -p "$DRACCUS_CACHE/spack-readonly-envs/$draccus_env_name"
        cp -a "$draccus_env_dir/." "$DRACCUS_CACHE/spack-readonly-envs/$draccus_env_name/"
      done
    fi
  fi

  # shellcheck source=draccus-view-dir.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-view-dir.sh"
  draccus_ensure_state_view_slot base-sys
  draccus_ensure_state_view_slot base-ml

  mkdir -p "$DRACCUS_BUNDLE/envs/base-sys" "$DRACCUS_BUNDLE/envs/base-ml"

  local -a gpu_args=()
  local -a driver_args=()

  # shellcheck source=draccus-nvidia-mounts.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-nvidia-mounts.sh"
  draccus_append_nvidia_mounts gpu_args driver_args

  local -a net_args=()
  if [[ "${DRACCUS_OFFLINE:-0}" == "1" ]]; then
    net_args+=(--unshare-net)
  fi

  local -a net_overlay_args=()
  if [[ "${DRACCUS_OFFLINE:-0}" != "1" ]]; then
    if [[ -r /etc/resolv.conf ]]; then
      exec {DRACCUS_FD_RESOLV}</etc/resolv.conf
      net_overlay_args+=(--ro-bind-data "$DRACCUS_FD_RESOLV" /etc/resolv.conf)
    fi
    if [[ -r /etc/hosts ]]; then
      exec {DRACCUS_FD_HOSTS}</etc/hosts
      net_overlay_args+=(--ro-bind-data "$DRACCUS_FD_HOSTS" /etc/hosts)
    fi
  fi

  local -a host_bin_args=()
  local -a mode_bind_args=()
  local -a mode_env_args=()
  local draccus_path_views
  local runtime_path
  local runtime_ld_library_path

  if [[ "$runtime_mode" == "run" ]]; then
    host_bin_args+=(--ro-bind "$DRACCUS_BUNDLE/host-bin" /opt/draccus/host-bin)
    mode_bind_args+=(
      --ro-bind "$DRACCUS_BUNDLE/shims" /opt/draccus/shims
      --ro-bind "$DRACCUS_BUNDLE/envs" /opt/draccus/envs
      --ro-bind "$DRACCUS_STATE/spack" /opt/draccus/spack
      --ro-bind "$DRACCUS_STATE/view" /opt/draccus/view
    )
    mode_env_args+=(
      --setenv SPACK_USER_CONFIG_PATH /opt/draccus/cache/spack-readonly-config
      --setenv UV_LINK_MODE copy
      --setenv PYTHONPATH /opt/draccus/view/base-ml/lib/python3.12/site-packages
    )

    # Host-only: default PATH lists base-ml before base-sys (Torch/JAX foundation `python`).
    # Pip/pip3 from Spack's py-pip are shadowed by bundle shims mounted at /opt/draccus/shims.
    draccus_path_views="/opt/draccus/shims:/opt/draccus/view/base-ml/bin:/opt/draccus/view/base-sys/bin:/opt/draccus/spack/bin:/opt/draccus/cache/starship/bin"
    if [[ "${DRACCUS_PREFER_SYS_PATH:-0}" =~ ^(1|true|yes)$ ]]; then
      draccus_path_views="/opt/draccus/shims:/opt/draccus/view/base-sys/bin:/opt/draccus/view/base-ml/bin:/opt/draccus/spack/bin:/opt/draccus/cache/starship/bin"
    fi
    runtime_path="${draccus_path_views}:/opt/draccus/host-bin:${DRACCUS_BWRAP_CUDA_BIN_PREFIX:-}/usr/local/nvidia/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    runtime_ld_library_path="/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/cuda/lib${cuda_ld_extra}:/opt/draccus/view/base-ml/lib:/opt/draccus/view/base-ml/lib64"
  else
    mode_bind_args+=(
      --bind "$DRACCUS_BUNDLE/envs" /opt/draccus/envs
      --bind "$DRACCUS_STATE/spack" /opt/draccus/spack
      --bind "$DRACCUS_STATE/view" /opt/draccus/view
    )
    runtime_path="/opt/draccus/view/base-sys/bin:/opt/draccus/view/base-ml/bin:${DRACCUS_BWRAP_CUDA_BIN_PREFIX:-}/usr/local/nvidia/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    runtime_ld_library_path="/usr/local/nvidia/lib:/usr/local/nvidia/lib64${cuda_ld_extra}:/usr/local/cuda/lib:/opt/draccus/view/base-ml/lib:/opt/draccus/view/base-ml/lib64"
  fi

  exec "$BWRAP" \
    --die-with-parent \
    --unshare-user \
    --uid 0 \
    --gid 0 \
    --unshare-ipc \
    --unshare-pid \
    --unshare-uts \
    "${net_args[@]}" \
    --ro-bind "$DRACCUS_ROOTFS" / \
    --tmpfs /opt \
    --ro-bind-try "$DRACCUS_ROOTFS/opt/nvidia" /opt/nvidia \
    --tmpfs /var \
    --bind "$DRACCUS_STATE/var-intel" /var/intel \
    --proc /proc \
    --dev /dev \
    --ro-bind-try /sys /sys \
    --tmpfs /tmp \
    --tmpfs /run \
    "${gpu_args[@]}" \
    "${host_bin_args[@]}" \
    "${driver_args[@]}" \
    "${net_overlay_args[@]}" \
    "${mode_bind_args[@]}" \
    --bind "$DRACCUS_CACHE" /opt/draccus/cache \
    --bind "$DRACCUS_BUILD" /opt/draccus/build \
    --bind "$DRACCUS_WORKSPACE" /workspace \
    "${uv_overrides_args[@]}" \
    --setenv DRACCUS_PREFIX /opt/draccus \
    --setenv SPACK_ROOT /opt/draccus/spack \
    --setenv SPACK_SYS_VIEW /opt/draccus/view/base-sys \
    --setenv SPACK_ML_VIEW /opt/draccus/view/base-ml \
    --setenv DRACCUS_SYS_VIEW /opt/draccus/view/base-sys \
    --setenv DRACCUS_ML_VIEW /opt/draccus/view/base-ml \
    "${mode_env_args[@]}" \
    --setenv SPACK_USER_CACHE_PATH /opt/draccus/cache/spack \
    --setenv UV_CACHE_DIR /opt/draccus/cache/uv \
    --setenv HF_HOME /opt/draccus/cache/huggingface \
    --setenv CUDA_HOME "$DRACCUS_RESOLVED_CUDA_HOME" \
    --setenv CUDA_ROOT "$DRACCUS_RESOLVED_CUDA_ROOT" \
    --setenv TORCH_CUDA_ARCH_LIST "10.0" \
    --setenv PYTHONNOUSERSITE "1" \
    --setenv HOME /workspace \
    --setenv DRACCUS_WORKSPACE /workspace \
    --setenv PATH "$runtime_path" \
    --setenv LD_LIBRARY_PATH "$runtime_ld_library_path" \
    --chdir /workspace \
    "$@"
}
