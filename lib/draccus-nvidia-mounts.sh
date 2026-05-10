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

  if command -v ldconfig >/dev/null 2>&1; then
    local canon resolved
    while IFS= read -r canon; do
      [[ "$canon" == /* ]] || continue
      resolved="$(readlink -f "$canon" 2>/dev/null || true)"
      [[ -z "$resolved" ]] && resolved="$canon"
      draccus__add_driver_dir "$(dirname "$resolved")"
    done < <(
      LC_ALL=C ldconfig -p 2>/dev/null \
        | LC_ALL=C awk '
            function path() {
              for (i = 1; i <= NF; i++) if ($i == "=>") return $(i + 1)
              return ""
            }
            /=>/ && $0 ~ /(libcuda\.so|libnvidia-ml\.so|libcudadebugger\.so)/ {
              p = path(); if (p ~ /^\//) print p
            }'
    )
  fi

}
