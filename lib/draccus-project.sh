# shellcheck shell=bash
# Draccus project-overlay library.
# Source this file; do not execute directly.

# shellcheck source=draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-env.sh"
# shellcheck source=draccus-layout.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-layout.sh"

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

draccus_project_apply_bundle_from_config() {
  local config="${1:-}"
  local bundle project_root selected_bundle
  if [[ -z "$config" ]]; then
    config="$(draccus_project_config_path)" || return 1
  fi

  bundle="$(draccus_project_bundle_from_config "$config")" || return 0
  project_root="$(dirname "$config")"
  case "$bundle" in
    /*)
      selected_bundle="$bundle"
      ;;
    *)
      selected_bundle="$project_root/$bundle"
      ;;
  esac

  if [[ ! -d "$selected_bundle" ]]; then
    echo "draccus: error: selected project bundle does not exist: $selected_bundle" >&2
    return 2
  fi

  DRACCUS_BUNDLE="$(cd "$selected_bundle" && pwd -P)"
  export DRACCUS_BUNDLE
  unset DRACCUS_ROOTFS DRACCUS_STATE DRACCUS_CACHE DRACCUS_BUILD
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

draccus_project_init_usage() {
  echo "Usage: draccus project init <name> [--path PATH]" >&2
}

draccus_project_do_not_shadow_packages() {
  local layering_script="$DRACCUS_BUNDLE/scripts/validate_uv_layering.sh"
  if [[ ! -f "$layering_script" ]]; then
    echo "draccus: error: cannot find $layering_script" >&2
    return 1
  fi

  local -a packages=()
  mapfile -t packages < <(
    awk '
      /^readonly -a DO_NOT_SHADOW=\(/ { flag = 1; next }
      flag && /^\)/ { exit }
      flag {
        gsub(/#.*/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        gsub(/"/, "")
        if (length > 0) print
      }
    ' "$layering_script"
  )

  if [[ ${#packages[@]} -eq 0 ]]; then
    echo "draccus: error: failed to parse DO_NOT_SHADOW from $layering_script" >&2
    return 1
  fi

  local required pkg found
  for required in torch jax jaxlib numpy scipy triton; do
    found=0
    for pkg in "${packages[@]}"; do
      if [[ "$pkg" == "$required" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -ne 1 ]]; then
      echo "draccus: error: parsed DO_NOT_SHADOW from $layering_script but missing sentinel '$required'" >&2
      return 1
    fi
  done

  printf "%s\n" "${packages[@]}"
}

draccus_project_validate_name() {
  local name="$1"

  if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "draccus: error: project name must be lowercase alphanumeric plus hyphens: '$name'" >&2
    return 1
  fi

  if [[ "$name" == nvidia-* ]]; then
    echo "draccus: error: project names starting with 'nvidia-' are forbidden" >&2
    return 1
  fi

  local shadow_packages pkg
  shadow_packages="$(draccus_project_do_not_shadow_packages)" || return 1

  while IFS= read -r pkg; do
    if [[ "$name" == "$pkg" ]]; then
      echo "draccus: error: '$name' is in the DO_NOT_SHADOW list (managed by Spack, not uv)" >&2
      return 1
    fi
  done <<<"$shadow_packages"
}

draccus_project_init_root() {
  local name="$1"
  local explicit_path="$2"
  local root git_root

  if [[ -n "$explicit_path" ]]; then
    root="$explicit_path"
  elif git_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ "$(cd "$git_root" && pwd -P)" != "$(cd "$DRACCUS_BUNDLE" && pwd -P)" ]]; then
    root="$git_root"
  else
    root="$(draccus_managed_projects_root)/$name"
  fi

  mkdir -p "$root"
  (cd "$root" && pwd -P)
}

draccus_project_init_main() {
  if [[ "${1:-}" == "init" ]]; then
    shift
  fi

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    draccus_project_init_usage
    return 0
  fi

  local name="${1:-}"
  if [[ -z "$name" ]]; then
    draccus_project_init_usage
    return 2
  fi
  shift

  local explicit_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "draccus: error: --path requires a value" >&2
          return 2
        fi
        explicit_path="$1"
        shift
        ;;
      *)
        echo "draccus: error: unknown project init argument: $1" >&2
        draccus_project_init_usage
        return 2
        ;;
    esac
  done

  draccus_project_validate_name "$name" || return 1

  local template_dir="$DRACCUS_BUNDLE/projects/_template"
  if [[ ! -d "$template_dir" ]]; then
    echo "draccus: error: missing project template: $template_dir" >&2
    return 1
  fi

  local root
  root="$(draccus_project_init_root "$name" "$explicit_path")"

  local config="$root/draccus.yaml"
  if [[ -f "$config" ]]; then
    local existing_name=""
    existing_name="$(draccus_yaml_value name "$config" 2>/dev/null || true)"
    if [[ -n "$existing_name" && "$existing_name" != "$name" ]]; then
      echo "draccus: error: existing draccus.yaml has name '$existing_name', refusing to initialize as '$name'" >&2
      return 1
    fi
  fi

  local created_pyproject=0
  if [[ ! -f "$root/pyproject.toml" ]]; then
    sed "s/REPLACE_ME/$name/g" "$template_dir/pyproject.toml" >"$root/pyproject.toml"
    created_pyproject=1
  fi
  if [[ ! -f "$root/.gitignore" ]]; then
    cp "$template_dir/.gitignore" "$root/.gitignore"
  fi
  if [[ ! -f "$root/README.md" && -f "$template_dir/README.md" ]]; then
    sed "s/REPLACE_ME/$name/g" "$template_dir/README.md" >"$root/README.md"
  fi

  if [[ ! -f "$config" ]]; then
    cat >"$config" <<EOF
name: $name
# bundle: /absolute/path/to/shared/draccus/bundle
# runs_dir: /absolute/path/to/run/artifacts
EOF
  fi

  # shellcheck source=draccus-runtime.sh
  source "${DRACCUS_CLI_ROOT:-$DRACCUS_BUNDLE}/lib/draccus-runtime.sh"

  (
    DRACCUS_WORKSPACE="$root" draccus_runtime_exec_run bash -lc '
      set -euo pipefail
      update_pyproject="$1"

      if [[ -r /opt/draccus/spack/share/spack/setup-env.sh ]]; then
        # shellcheck disable=SC1091
        . /opt/draccus/spack/share/spack/setup-env.sh
        spack env activate -p base-ml 2>/dev/null || true
      fi

      if ! command -v python >/dev/null 2>&1; then
        python_fallback="$(command -v python3 || command -v python3.12 || true)"
        if [[ -z "$python_fallback" ]]; then
          echo "draccus: error: no Python interpreter found in runtime" >&2
          exit 1
        fi
        mkdir -p /tmp/draccus-python-bin
        ln -sf "$python_fallback" /tmp/draccus-python-bin/python
        export PATH="/tmp/draccus-python-bin:$PATH"
      fi

      py_ver="$(python -c '\''import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'\'')"
      printf "%s\n" "$py_ver" >/workspace/.python-version

      if [[ "$update_pyproject" == "1" ]]; then
        req_line="requires-python = \">=$py_ver\""
        if grep -Eq "^[[:space:]]*requires-python[[:space:]]*=" /workspace/pyproject.toml; then
          sed -i "s/^[[:space:]]*requires-python[[:space:]]*=.*/$req_line/" /workspace/pyproject.toml
        else
          tmp="$(mktemp)"
          awk -v req="$req_line" '"'"'
            /^\[project\]$/ && !inserted {
              print
              print req
              inserted = 1
              next
            }
            { print }
            END {
              if (!inserted) {
                print "[project]"
                print req
              }
            }
          '"'"' /workspace/pyproject.toml >"$tmp"
          mv "$tmp" /workspace/pyproject.toml
        fi
      fi

      if [[ ! -f /workspace/.venv/pyvenv.cfg ]]; then
        uv venv --python "$(which python)" --system-site-packages /workspace/.venv
      fi
      cd /workspace
      uv lock
    ' bash "$created_pyproject"
  )

  draccus_project_neutralize_pip "$root/.venv"

  echo "Initialized Draccus project at $root"
}
