#!/usr/bin/env bash
# Populates Bubblewrap gpu_args and driver_args for NVIDIA devices/drivers (EDD §7.3 extensions).
#
# Caller must initialize:
#   gpu_args=(); driver_args=()
# Then: draccus_append_nvidia_mounts gpu_args driver_args

draccus_append_nvidia_mounts() {
  local -n _gpu_arr="$1"
  local -n _drv_arr="$2"
  declare -A _drv_seen_paths

  draccus__add_driver_dir() {
    local d="$1"
    [[ -z "$d" || ! -d "$d" ]] && return 0
    case "$d" in
      "/") return 0 ;;
    esac
    [[ -n "${_drv_seen_paths[$d]:-}" ]] && return 0
    _drv_seen_paths[$d]=1
    _drv_arr+=(--ro-bind-try "$d" "$d")
  }

  draccus__maybe_ro_bind_so() {
    local shim="$1"
    local canon=""
    [[ -e "$shim" ]] || return 0
    canon="$(readlink -f "$shim" 2>/dev/null || true)"
    [[ -z "${canon:-}" ]] && canon="$shim"
    [[ -r "$canon" ]] || return 0
    _drv_arr+=(--ro-bind-try "$canon" "$shim")
  }

  draccus__maybe_ro_bind_host_bin() {
    local src="$1"
    local dest="$2"
    [[ -x "$src" ]] || return 0
    _drv_arr+=(--ro-bind-try "$src" "$dest")
  }

  local dev

  # Classic device nodes + full caps directory where present (never assume specific cap minor numbers).
  for dev in \
    /dev/nvidiactl \
    /dev/nvidia-uvm \
    /dev/nvidia-uvm-tools \
    /dev/nvidia-modeset \
    /dev/nvidia[0-9]*; do
    [[ -e "$dev" ]] && _gpu_arr+=(--dev-bind-try "$dev" "$dev")
  done

  if [[ -d /dev/nvidia-caps ]]; then
    _gpu_arr+=(--dev-bind-try /dev/nvidia-caps /dev/nvidia-caps)
  fi

  # IB pass-through unchanged from EDD
  if [[ -d /dev/infiniband ]]; then
    _gpu_arr+=(--dev-bind-try /dev/infiniband /dev/infiniband)
  fi

  draccus__add_driver_dir "/usr/local/nvidia"
  draccus__maybe_ro_bind_host_bin /usr/bin/nvidia-smi /opt/draccus/host-bin/nvidia-smi
  draccus__maybe_ro_bind_host_bin /usr/local/nvidia/bin/nvidia-smi /opt/draccus/host-bin/nvidia-smi

  local canon ldconfig_seen=false
  if command -v ldconfig >/dev/null 2>&1; then
    while IFS= read -r canon; do
      [[ "$canon" == /* ]] || continue
      ldconfig_seen=true
      draccus__maybe_ro_bind_so "$canon"
    done < <(
      LC_ALL=C ldconfig -p 2>/dev/null \
        | LC_ALL=C awk '
            function path() {
              for (i = 1; i <= NF; i++) if ($i == "=>") return $(i + 1)
              return ""
            }
            /=>/ && $0 ~ /(libcuda\.so\.1|libnvidia-ml\.so\.1|libcudadebugger\.so\.1)/ {
              p = path(); if (p ~ /^\//) print p
            }'
    )
  fi

  # If ld.so.cache is broken (often Nix + vendor glibc hybrids), ldconfig emits nothing.
  # Bind individual driver SONAME shim paths instead of whole lib dirs: binding a host
  # system lib directory would shadow rootfs glibc and break rootfs binaries.
  if [[ "$ldconfig_seen" != true ]]; then
    draccus__maybe_ro_bind_so /usr/lib/x86_64-linux-gnu/libcuda.so.1
    draccus__maybe_ro_bind_so /usr/lib64/libcuda.so.1
    draccus__maybe_ro_bind_so /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
    draccus__maybe_ro_bind_so /usr/lib64/libnvidia-ml.so.1
    draccus__maybe_ro_bind_so /usr/lib/x86_64-linux-gnu/libcudadebugger.so.1
    draccus__maybe_ro_bind_so /usr/lib64/libcudadebugger.so.1
  fi

}
