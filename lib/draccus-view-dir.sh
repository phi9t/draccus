#!/usr/bin/env bash
# Prepare state/view/<name> so Spack can materialize env views (prefer symlink layouts).
#
# Spack installs a symlink: view/base-{sys,ml} -> ._base-{sys,ml}/<hash>. Blank directories or
# broken symlinks block `spack env view regenerate`; we never `mkdir -p "$slot"` anymore.
#
# Caller must set DRACCUS_STATE; callers mkdir -p `"$DRACCUS_STATE/view"` beforehand.
draccus_ensure_state_view_slot() {
  local name="${1:?}"
  local d="${DRACCUS_STATE:?}/view/${name}"

  [[ -z "${DRACCUS_STATE:-}" ]] && return 1

  mkdir -p "${DRACCUS_STATE}/view"

  # Spack's view symlink targets look like /opt/draccus/view/._<env>/… (absolute paths
  # inside bwrap). On the host, /opt/draccus/view is not mounted, so [[ -e "$d" ]] is false
  # even though the shadow directory exists under $DRACCUS_STATE/view. Removing that
  # symlink here would strip base-sys/base-ml from PATH on every draccus-{build,run}.
  if [[ -L "$d" ]] && [[ ! -e "$d" ]]; then
    local tgt
    tgt="$(readlink "$d" || true)"
    if [[ "$tgt" == /opt/draccus/view/* ]]; then
      local rel="${tgt#/opt/draccus/view/}"
      if [[ -e "${DRACCUS_STATE}/view/${rel}" ]]; then
        return 0
      fi
    fi
    rm -f "$d"
    return 0
  fi

  if [[ -f "$d" ]]; then
    rm -f "$d"
    return 0
  fi

  if [[ -d "$d" ]] && [[ ! -L "$d" ]]; then
    if [[ -z "$(find "$d" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      rmdir "$d" || true
    fi
    return 0
  fi
}
