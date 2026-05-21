# shellcheck shell=bash
# Draccus project notebook launcher.
# Source this file; do not execute directly.

# shellcheck source=draccus-project.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-project.sh"

draccus_notebook_main() {
  local port="8888"
  local host="127.0.0.1"
  local config project_root

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "draccus notebook: --port requires a value" >&2
          return 2
        fi
        port="$1"
        shift
        ;;
      --host)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "draccus notebook: --host requires a value" >&2
          return 2
        fi
        host="$1"
        shift
        ;;
      *)
        echo "draccus notebook: unknown argument '$1'" >&2
        return 2
        ;;
    esac
  done

  config="$(draccus_project_config_path)" || {
    echo "draccus: error: no draccus.yaml found. Run: draccus project init <name>" >&2
    return 1
  }
  project_root="$(draccus_project_root_from_config "$config")"
  draccus_project_apply_bundle_from_config "$config" || return $?

  # shellcheck source=draccus-runtime.sh
  source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

  DRACCUS_WORKSPACE="$project_root" draccus_runtime_exec_run bash -lc '
    set -euo pipefail
    if ! python -c "import jupyterlab" >/dev/null 2>&1; then
      echo "JupyterLab is not installed. Run: draccus uv pip install jupyterlab" >&2
      exit 2
    fi
    exec python -m jupyterlab --ip="$1" --port="$2" --no-browser
  ' bash "$host" "$port"
}
