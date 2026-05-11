# shellcheck shell=bash
# Draccus project-overlay library.
# Source this file; do not execute directly.

# shellcheck source=draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-env.sh"

# Echo the absolute path of the nearest project root.
# A project root is a directory that:
#   1. Contains a pyproject.toml, AND
#   2. Is a direct child of a directory named "projects".
# Returns nonzero if the caller is not inside a project.
draccus_project_root() {
  local dir parent
  dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    parent="$(dirname "$dir")"
    if [[ -f "$dir/pyproject.toml" ]] && [[ "$(basename "$parent")" == "projects" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$parent"
  done
  return 1
}

# Echo the canonical .venv path for the current project.
draccus_project_venv_path() {
  local root
  root="$(draccus_project_root)" || return 1
  echo "$root/.venv"
}

# Exit 1 with an error message if the caller is not inside a draccus project.
draccus_project_assert_inside() {
  if ! draccus_project_root >/dev/null 2>&1; then
    echo "draccus: error: not inside a draccus project (no pyproject.toml found under a projects/ parent)" >&2
    exit 1
  fi
}

# Echo the canonical uv venv creation arguments.
# This is THE source-of-truth invocation; callers eval inside bwrap where
# $(which python) resolves to the Spack base-ml Python.
# shellcheck disable=SC2016
draccus_project_uv_venv_args() {
  echo '--python "$(which python)" --system-site-packages .venv'
}
