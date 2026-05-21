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

# Echo the nearest draccus.yaml discovered by walking upward from $PWD.
draccus_project_config_path() {
  local dir parent
  dir="$PWD"

  while :; do
    if [[ -f "$dir/draccus.yaml" ]]; then
      echo "$dir/draccus.yaml"
      return 0
    fi
    [[ "$dir" == "/" ]] && break
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done

  return 1
}

# Echo the directory that contains the active draccus.yaml.
draccus_project_root_from_config() {
  local config="${1:-}"
  if [[ -z "$config" ]]; then
    config="$(draccus_project_config_path)" || return 1
  fi

  dirname "$config"
}

# Parse a simple top-level "key: value" pair from a first-schema draccus.yaml.
draccus_yaml_value() {
  if [[ $# -ne 2 ]]; then
    echo "draccus_yaml_value: expected KEY FILE" >&2
    return 2
  fi

  local key="$1"
  local file="$2"

  awk -v key="$key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function strip_comment(value,    i, char, prev, in_single, in_double) {
      for (i = 1; i <= length(value); i++) {
        char = substr(value, i, 1)
        prev = i > 1 ? substr(value, i - 1, 1) : ""

        if (char == "\"" && !in_single && prev != "\\") {
          in_double = !in_double
        } else if (char == "'\''" && !in_double) {
          in_single = !in_single
        } else if (char == "#" && !in_single && !in_double && (i == 1 || prev ~ /[[:space:]]/)) {
          return substr(value, 1, i - 1)
        }
      }
      return value
    }

    $0 ~ ("^" key "[[:space:]]*:") {
      value = $0
      sub("^" key "[[:space:]]*:[[:space:]]*", "", value)
      value = strip_comment(value)
      value = trim(value)
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      found = 1
      exit
    }

    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
}

draccus_project_name_from_config() {
  local config="${1:-}"
  local name
  if [[ -z "$config" ]]; then
    config="$(draccus_project_config_path)" || return 1
  fi

  name="$(draccus_yaml_value name "$config")" || return 1
  [[ -n "$name" ]] || return 1
  echo "$name"
}

draccus_project_bundle_from_config() {
  local config="${1:-}"
  local bundle
  if [[ -z "$config" ]]; then
    config="$(draccus_project_config_path)" || return 1
  fi

  bundle="$(draccus_yaml_value bundle "$config")" || return 1
  [[ -n "$bundle" ]] || return 1
  echo "$bundle"
}

draccus_project_runs_dir_from_config() {
  local config="${1:-}"
  local runs_dir
  if [[ -z "$config" ]]; then
    config="$(draccus_project_config_path)" || return 1
  fi

  runs_dir="$(draccus_yaml_value runs_dir "$config")" || return 1
  [[ -n "$runs_dir" ]] || return 1
  echo "$runs_dir"
}

draccus_project_assert_config() {
  if ! draccus_project_config_path >/dev/null 2>&1; then
    echo "draccus: error: no draccus.yaml found. Run: draccus project init <name>" >&2
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

# Replace .venv pip stubs with the bundle pip shim (copies $DRACCUS_BUNDLE/shims/pip — no inline body).
draccus_project_neutralize_pip() {
  local vdir="$1"
  local shim="${DRACCUS_BUNDLE}/shims/pip"

  if [[ ! -f "$shim" ]]; then
    echo "draccus_project_neutralize_pip: missing shim ${shim}" >&2
    return 1
  fi
  if [[ ! -d "${vdir}/bin" ]]; then
    echo "draccus_project_neutralize_pip: missing ${vdir}/bin" >&2
    return 1
  fi
  if [[ ! -f "${vdir}/pyvenv.cfg" ]]; then
    echo "draccus_project_neutralize_pip: not a venv (missing ${vdir}/pyvenv.cfg)" >&2
    return 1
  fi

  install -m 0755 "$shim" "${vdir}/bin/pip"
  install -m 0755 "$shim" "${vdir}/bin/pip3"

  local path
  shopt -s nullglob
  for path in "${vdir}/bin/pip3."*; do
    [[ -e "$path" ]] || continue
    [[ "$path" -ef "${vdir}/bin/pip3" ]] && continue
    install -m 0755 "$shim" "$path"
  done
  shopt -u nullglob
}
