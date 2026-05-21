#!/usr/bin/env bash
# Materialize Draccus rootfs via one of two backends:
#
#   docker (default)  – export NVIDIA CUDA + cuDNN Ubuntu Docker image tarball to rootfs
#   debootstrap       – Debian minbase (+ python3-minimal etc.) legacy path
#
# Docker mode aligns the pinned inner userland ABI with NVIDIA's CUDA toolkit layout
# at /usr/local/cuda plus Ubuntu 24.04 glibc/OpenSSL tooling.
#
# Requires: sudo, bubblewrap-friendly directory layout stubs (see finalize_rootfs_overlay),
# Docker CLI for docker mode OR debootstrap for debootstrap mode.
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"

draccus_umount_descendants_of() {
  local root="${1%/}"
  if [[ ! -d "$root" ]]; then
    return 0
  fi

  LC_ALL=C awk -v p="$root" '$2 ~ "^" p "(/|$)" {print $2}' /proc/mounts \
    | LC_ALL=C sort -r \
    | while IFS= read -r mpath; do
      sudo umount -lf "$mpath" 2>/dev/null || true
    done
}

DRACCUS_ROOTFS="${DRACCUS_ROOTFS:-$DRACCUS_BUNDLE/rootfs}"
DRACCUS_ROOTFS_MODE="${DRACCUS_ROOTFS_MODE:-docker}"
DRACCUS_DOCKER_CLI="${DRACCUS_DOCKER_CLI:-docker}"

# Verified on 2026-05-10; override with DRACCUS_CUDA_DOCKER_IMAGE to track newer NVIDIA tags.
DRACCUS_CUDA_DOCKER_IMAGE="${DRACCUS_CUDA_DOCKER_IMAGE:-nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04}"

finalize_rootfs_overlay() {
  echo "[bootstrap-rootfs] bind-mount stubs + optional network snapshot"
  local _stub
  sudo mkdir -p "${DRACCUS_ROOTFS%/}/usr/local/bin"

  sudo mkdir -p \
    "$DRACCUS_ROOTFS/opt/draccus/spack" \
    "$DRACCUS_ROOTFS/opt/draccus/view" \
    "$DRACCUS_ROOTFS/opt/draccus/cache" \
    "$DRACCUS_ROOTFS/opt/draccus/build" \
    "$DRACCUS_ROOTFS/opt/draccus/envs" \
    "$DRACCUS_ROOTFS/workspace" \
    "$DRACCUS_ROOTFS/usr/lib/x86_64-linux-gnu"
  # Placeholders for host-driver bind-mount targets (bubblewrap cannot create new files under ro-bind "/").
  for _stub in libcuda.so.1 libnvidia-ml.so.1 libcudadebugger.so.1; do
    sudo touch "$DRACCUS_ROOTFS/usr/lib/x86_64-linux-gnu/${_stub}"
  done

  sudo chmod 0755 \
    "$DRACCUS_ROOTFS/opt" \
    "$DRACCUS_ROOTFS/opt/draccus" \
    "$DRACCUS_ROOTFS/opt/draccus/envs" \
    "$DRACCUS_ROOTFS/workspace"

  if [[ "${DRACCUS_ROOTFS_EMBED_NET_FILES:-1}" =~ ^1$ ]]; then
    if [[ -r /etc/hosts ]]; then
      sudo cp /etc/hosts "$DRACCUS_ROOTFS/etc/hosts"
    fi
    if [[ -r /etc/resolv.conf ]]; then
      sudo cp /etc/resolv.conf "$DRACCUS_ROOTFS/etc/resolv.conf"
    fi
  fi

  TZDATA_DEB="${TZDATA_DEB:-Etc/UTC}"
  if [[ -d "$DRACCUS_ROOTFS/usr/share/zoneinfo" ]]; then
    sudo ln -sf "/usr/share/zoneinfo/$TZDATA_DEB" "$DRACCUS_ROOTFS/etc/localtime"
  fi

  # Duplicate NVIDIA APT entries (one Signed-By, one not) prevent apt-get update in Ubuntu 24.04+ images.
  if [[ -f "$DRACCUS_ROOTFS/etc/apt/sources.list.d/cuda.list" ]] \
    && [[ -f "$DRACCUS_ROOTFS/etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list" ]]; then
    sudo rm -f "$DRACCUS_ROOTFS/etc/apt/sources.list.d/cuda.list"
  fi
}

bootstrap_debootstrap_impl() {
  local DEB_MIRROR="${DEB_MIRROR:-http://deb.debian.org/debian}"
  local DEB_SUITE="${DEB_SUITE:-bookworm}"

  local EXTRA_PKGS=(
    bash
    ca-certificates
    curl
    wget
    coreutils
    grep
    sed
    gawk
    findutils
    git
    iproute2
    iputils-ping
    locales
    openssl
    python3-minimal
  )

  local INCLUDE
  INCLUDE=$(
    IFS=,
    echo "${EXTRA_PKGS[*]}"
  )
  sudo mkdir -p "$DRACCUS_ROOTFS"
  sudo debootstrap \
    --variant=minbase \
    --include="$INCLUDE" \
    "$DEB_SUITE" \
    "$DRACCUS_ROOTFS" \
    "$DEB_MIRROR"
}

export_docker_cuda_rootfs_impl() {
  if ! "${DRACCUS_DOCKER_CLI}" info >/dev/null 2>&1; then
    echo "[bootstrap-rootfs] ${DRACCUS_DOCKER_CLI}: daemon unreachable; fix Docker/podman connectivity" >&2
    exit 1
  fi

  sudo mkdir -p "$DRACCUS_ROOTFS"
  echo "[bootstrap-rootfs] pulling Docker image ${DRACCUS_CUDA_DOCKER_IMAGE}"
  "${DRACCUS_DOCKER_CLI}" pull "${DRACCUS_CUDA_DOCKER_IMAGE}"

  local cid
  cid="$("${DRACCUS_DOCKER_CLI}" create "${DRACCUS_CUDA_DOCKER_IMAGE}")"
  echo "[bootstrap-rootfs] exporting filesystem from container ${cid} (streaming tar)"
  if ! "${DRACCUS_DOCKER_CLI}" export "$cid" | sudo tar -x -C "$DRACCUS_ROOTFS"; then
    "${DRACCUS_DOCKER_CLI}" rm "$cid" >/dev/null 2>&1 || true
    echo "[bootstrap-rootfs] docker export failed" >&2
    exit 1
  fi
  "${DRACCUS_DOCKER_CLI}" rm "$cid" >/dev/null

  printf '%s\n' "${DRACCUS_CUDA_DOCKER_IMAGE}" | sudo tee "$DRACCUS_ROOTFS/.draccus-cuda-docker-image" >/dev/null || true

}

maybe_chroot_upgrade_packages() {
  if [[ "${DRACCUS_ROOTFS_CHROOT_APT:-1}" != "1" ]]; then
    return 0
  fi

  if [[ "${DRACCUS_ROOTFS_MODE}" != "docker" ]]; then
    return 0
  fi

  if [[ ! -x "$DRACCUS_ROOTFS/usr/bin/apt-get" ]]; then
    echo "[bootstrap-rootfs] skipping apt chroot tweaks (missing /usr/bin/apt-get)" >&2
    return 0
  fi

  sudo mkdir -p "$DRACCUS_ROOTFS/dev/pts"
  sudo mountpoint -q "$DRACCUS_ROOTFS/proc" 2>/dev/null || sudo mount --bind /proc "$DRACCUS_ROOTFS/proc"
  sudo mountpoint -q "$DRACCUS_ROOTFS/sys" 2>/dev/null || sudo mount --bind /sys "$DRACCUS_ROOTFS/sys"
  sudo mountpoint -q "$DRACCUS_ROOTFS/dev" 2>/dev/null || sudo mount --bind /dev "$DRACCUS_ROOTFS/dev"
  sudo mountpoint -q "$DRACCUS_ROOTFS/dev/pts" 2>/dev/null || sudo mount -t devpts devpts "$DRACCUS_ROOTFS/dev/pts"

  cleanup_mounts() {
    sudo umount "$DRACCUS_ROOTFS/dev/pts" 2>/dev/null || true
    sudo umount "$DRACCUS_ROOTFS/dev" 2>/dev/null || true
    sudo umount "$DRACCUS_ROOTFS/sys" 2>/dev/null || true
    sudo umount "$DRACCUS_ROOTFS/proc" 2>/dev/null || true
  }

  trap cleanup_mounts EXIT

  local tz="${DRACCUS_ROOTFS_TZ:-Etc/UTC}"
  printf '%s\n' "$tz" | sudo tee "$DRACCUS_ROOTFS/etc/timezone" >/dev/null
  sudo ln -sf "/usr/share/zoneinfo/${tz}" "$DRACCUS_ROOTFS/etc/localtime"

  export DEBIAN_FRONTEND=noninteractive
  export LC_ALL=C.UTF-8
  local PKG_LIST
  PKG_LIST="${DRACCUS_ROOTFS_EXTRA_APT_PACKAGES:-autoconf automake cmake gfortran-13 git git-lfs libtool m4 ninja-build pkg-config python3-minimal unzip ca-certificates curl wget}"

  sudo LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive chroot "$DRACCUS_ROOTFS" env PKG_LIST="$PKG_LIST" bash -lc '
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true DEBCONF_NOWARNINGS=true
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y -qq ${PKG_LIST}
    dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
  '

  trap - EXIT
  cleanup_mounts
}

docker_rootfs_populated_p() {
  [[ -s "$DRACCUS_ROOTFS/etc/os-release" ]] || return 1
  grep -q '^ID=' "$DRACCUS_ROOTFS/etc/os-release" || return 1
  grep -qi '^ID=ubuntu' "$DRACCUS_ROOTFS/etc/os-release" || return 1
  [[ -x "$DRACCUS_ROOTFS/usr/local/cuda/bin/nvcc" ]] || [[ -f "$DRACCUS_ROOTFS/usr/local/cuda/version.json" ]] || return 1
}

debootstrap_populated_p() {
  [[ -x "$DRACCUS_ROOTFS/bin/bash" ]] && [[ -x "$DRACCUS_ROOTFS/usr/bin/git" ]] && [[ -e "$DRACCUS_ROOTFS/usr/bin/python3" ]]
}

bootstrap_uv_into_rootfs() {
  # shellcheck disable=SC1091
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uv-version.env"
  [[ -n "${UV_VERSION:-}" ]] || {
    echo "[bootstrap-rootfs] UV_VERSION unset (scripts/uv-version.env)" >&2
    exit 1
  }
  [[ "${#UV_SHA256}" -eq 64 ]] || {
    echo "[bootstrap-rootfs] UV_SHA256 must be 64 hex chars in scripts/uv-version.env" >&2
    exit 1
  }

  if [[ -x "$DRACCUS_ROOTFS/usr/local/bin/uv" ]] \
    && "$DRACCUS_ROOTFS/usr/local/bin/uv" --version 2>/dev/null | grep -qF "$UV_VERSION"; then
    echo "[bootstrap-rootfs] uv ${UV_VERSION} already present at rootfs usr/local/bin/uv"
    return 0
  fi

  mkdir -p "$DRACCUS_BUNDLE/state/cache"
  local url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz"
  local tgz="$DRACCUS_BUNDLE/state/cache/uv-${UV_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
  echo "[bootstrap-rootfs] fetching uv ${UV_VERSION} (${url})"

  local attempt=1 max=5 delay=2
  while [[ "$attempt" -le "$max" ]]; do
    if curl -fsSL --retry 3 --retry-delay 2 -o "${tgz}.partial" "$url"; then
      mv -f "${tgz}.partial" "$tgz"
      break
    fi
    echo "[bootstrap-rootfs] uv download attempt ${attempt}/${max} failed; sleeping ${delay}s" >&2
    rm -f "${tgz}.partial"
    if [[ "$attempt" -eq "$max" ]]; then
      echo "[bootstrap-rootfs] uv download failed after ${max} attempts" >&2
      exit 1
    fi
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done

  local obs
  obs="$(sha256sum "$tgz" | awk '{print $1}')"
  if [[ "$obs" != "$UV_SHA256" ]]; then
    echo "[bootstrap-rootfs] uv tarball sha256 mismatch (expected ${UV_SHA256}, got ${obs}); refusing to extract" >&2
    rm -f "$tgz"
    exit 1
  fi

  local tmp uv_bin=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/uv-download.XXXXXX")"
  tar -xzf "$tgz" -C "$tmp"

  if [[ -f "$tmp/uv" ]]; then
    uv_bin="$tmp/uv"
  else
    uv_bin="$(find "$tmp" -maxdepth 4 -type f -name uv 2>/dev/null | head -n 1)"
  fi

  if [[ -z "$uv_bin" || ! -f "$uv_bin" ]]; then
    echo "[bootstrap-rootfs] could not find uv executable in release tarball layout" >&2
    rm -rf "$tmp"
    exit 1
  fi

  sudo install -m 0755 "$uv_bin" "$DRACCUS_ROOTFS/usr/local/bin/uv"
  rm -rf "$tmp"
  echo "[bootstrap-rootfs] installed uv ${UV_VERSION} -> ${DRACCUS_ROOTFS}/usr/local/bin/uv"
}

populate_rootfs_maybe() {
  case "$DRACCUS_ROOTFS_MODE" in
    docker)
      if docker_rootfs_populated_p && [[ "${DRACCUS_ROOTFS_FORCE:-}" != "1" ]]; then
        echo "[bootstrap-rootfs] Docker CUDA/Ubuntu rootfs already populated; DRACCUS_ROOTFS_FORCE=1 to refresh"
      else
        if [[ "${DRACCUS_ROOTFS_FORCE:-}" == "1" ]]; then
          echo "[bootstrap-rootfs] wiping ${DRACCUS_ROOTFS} via sudo..."
          draccus_umount_descendants_of "$DRACCUS_ROOTFS"
          sudo mkdir -p /tmp/.draccus-empty
          sudo rsync -a --delete --no-compress --info=NONE /tmp/.draccus-empty/ "${DRACCUS_ROOTFS%/}/"
        fi
        export_docker_cuda_rootfs_impl
      fi
      ;;
    debootstrap)
      if debootstrap_populated_p && [[ "${DRACCUS_ROOTFS_FORCE:-}" != "1" ]]; then
        echo "[bootstrap-rootfs] Debian rootfs already populated; DRACCUS_ROOTFS_FORCE=1 to rerun debootstrap"
      else
        if [[ "${DRACCUS_ROOTFS_FORCE:-}" == "1" ]]; then
          echo "[bootstrap-rootfs] wiping ${DRACCUS_ROOTFS} via sudo..."
          draccus_umount_descendants_of "$DRACCUS_ROOTFS"
          sudo rm -rf "${DRACCUS_ROOTFS:?}/"*
        fi
        bootstrap_debootstrap_impl
      fi
      ;;
    *)
      echo "Unknown DRACCUS_ROOTFS_MODE=$DRACCUS_ROOTFS_MODE (use docker or debootstrap)" >&2
      exit 2
      ;;
  esac
}

populate_rootfs_maybe
finalize_rootfs_overlay
maybe_chroot_upgrade_packages
bootstrap_uv_into_rootfs

echo "[bootstrap-rootfs] done (${DRACCUS_ROOTFS_MODE}): $DRACCUS_ROOTFS"
