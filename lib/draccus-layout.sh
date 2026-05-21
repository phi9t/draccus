# shellcheck shell=bash
# Shared Draccus host-side layout helpers.
# Source this file; do not execute directly.

draccus_home() {
  echo "${DRACCUS_HOME:-$HOME/.automata/draccus}"
}

draccus_default_bundle() {
  echo "${DRACCUS_DEFAULT_BUNDLE:-$(draccus_home)/bundles/default}"
}

draccus_runs_root() {
  echo "${DRACCUS_RUNS_ROOT:-$(draccus_home)/runs}"
}

draccus_managed_projects_root() {
  echo "${DRACCUS_PROJECTS_ROOT:-$(draccus_home)/projects}"
}

draccus_hash_path() {
  if [[ $# -ne 1 ]]; then
    echo "draccus_hash_path: expected path" >&2
    return 2
  fi

  printf '%s' "$1" | sha256sum | awk '{print substr($1, 1, 12)}'
}

draccus_slug() {
  local raw="${1:-}"
  local slug

  slug="$(
    printf '%s' "$raw" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9._-]+/-/g; s/^[-.]+//; s/[-.]+$//'
  )"
  if [[ -z "$slug" ]]; then
    slug="project"
  fi

  echo "$slug"
}

draccus_timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}
