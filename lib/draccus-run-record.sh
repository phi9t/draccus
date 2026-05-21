# shellcheck shell=bash
# Project-bound draccus run recording helpers.
# Source this file; do not execute directly.

# shellcheck source=draccus-layout.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-layout.sh"
# shellcheck source=draccus-project.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-project.sh"

_draccus_run_json_string() {
  if declare -F draccus_json_string >/dev/null 2>&1; then
    draccus_json_string "$1"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    DRACCUS_JSON_VALUE="${1:-}" python3 -c 'import json, os; print(json.dumps(os.environ["DRACCUS_JSON_VALUE"]))'
    return 0
  fi

  DRACCUS_JSON_VALUE="${1:-}" python -c 'import json, os; print(json.dumps(os.environ["DRACCUS_JSON_VALUE"]))'
}

_draccus_run_json_array() {
  local out="[" sep="" value
  for value in "$@"; do
    out+="$sep$(_draccus_run_json_string "$value")"
    sep=","
  done
  out+="]"
  printf '%s\n' "$out"
}

_draccus_run_resolve_runs_dir() {
  local project_root="$1"
  local runs_dir="$2"

  case "$runs_dir" in
    /*)
      printf '%s\n' "$runs_dir"
      ;;
    *)
      printf '%s\n' "$project_root/$runs_dir"
      ;;
  esac
}

_draccus_run_write_start_record() {
  local run_dir="$1"
  local run_id="$2"
  local started_at="$3"
  local original_cwd="$4"
  local project_root="$5"
  local project_name="$6"
  local project_id="$7"
  local bundle_path="$8"
  shift 8

  local command_argv
  command_argv="$(_draccus_run_json_array "$@")"

  printf '{\n' >"$run_dir/run.json"
  printf '  "schema_version": 1,\n' >>"$run_dir/run.json"
  printf '  "run_id": %s,\n' "$(_draccus_run_json_string "$run_id")" >>"$run_dir/run.json"
  printf '  "started_at": %s,\n' "$(_draccus_run_json_string "$started_at")" >>"$run_dir/run.json"
  printf '  "command_argv": %s,\n' "$command_argv" >>"$run_dir/run.json"
  printf '  "original_cwd": %s,\n' "$(_draccus_run_json_string "$original_cwd")" >>"$run_dir/run.json"
  printf '  "project_root": %s,\n' "$(_draccus_run_json_string "$project_root")" >>"$run_dir/run.json"
  printf '  "project_name": %s,\n' "$(_draccus_run_json_string "$project_name")" >>"$run_dir/run.json"
  printf '  "project_id": %s,\n' "$(_draccus_run_json_string "$project_id")" >>"$run_dir/run.json"
  printf '  "bundle_path": %s\n' "$(_draccus_run_json_string "$bundle_path")" >>"$run_dir/run.json"
  printf '}\n' >>"$run_dir/run.json"
}

_draccus_run_write_result_record() {
  local run_dir="$1"
  local run_id="$2"
  local finished_at="$3"
  local exit_code="$4"

  printf '{\n' >"$run_dir/result.json"
  printf '  "schema_version": 1,\n' >>"$run_dir/result.json"
  printf '  "run_id": %s,\n' "$(_draccus_run_json_string "$run_id")" >>"$run_dir/result.json"
  printf '  "finished_at": %s,\n' "$(_draccus_run_json_string "$finished_at")" >>"$run_dir/result.json"
  printf '  "exit_code": %s,\n' "$exit_code" >>"$run_dir/result.json"
  printf '  "stdout_log": %s,\n' "$(_draccus_run_json_string "logs/stdout.log")" >>"$run_dir/result.json"
  printf '  "stderr_log": %s\n' "$(_draccus_run_json_string "logs/stderr.log")" >>"$run_dir/result.json"
  printf '}\n' >>"$run_dir/result.json"
}

draccus_run_main() {
  local name="" no_record=0 runs_dir="" saw_separator=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "draccus: error: --name requires a value" >&2
          return 2
        fi
        name="$1"
        shift
        ;;
      --no-record)
        no_record=1
        shift
        ;;
      --runs-dir)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "draccus: error: --runs-dir requires a value" >&2
          return 2
        fi
        runs_dir="$1"
        shift
        ;;
      --)
        saw_separator=1
        shift
        break
        ;;
      -*)
        echo "draccus: error: unknown run option: $1" >&2
        return 2
        ;;
      *)
        echo "draccus: error: expected '--' before run command" >&2
        return 2
        ;;
    esac
  done

  if [[ "$saw_separator" -ne 1 || $# -eq 0 ]]; then
    echo "draccus: error: run requires a command; usage: draccus run [--name NAME] [--no-record] [--runs-dir DIR] -- <cmd> [args...]" >&2
    return 2
  fi

  local config project_root project_name project_hash project_id bundle_path original_cwd
  config="$(draccus_project_config_path)" || {
    echo "draccus: error: no draccus.yaml found. Run: draccus project init <name>" >&2
    return 1
  }
  project_root="$(draccus_project_root_from_config "$config")"
  project_root="$(cd "$project_root" && pwd -P)"
  project_name="$(draccus_project_name_from_config "$config")" || {
    echo "draccus: error: draccus.yaml must define non-empty project name" >&2
    return 1
  }

  draccus_project_apply_bundle_from_config "$config" || return $?

  # shellcheck source=draccus-runtime.sh
  source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

  bundle_path="$(cd "$DRACCUS_BUNDLE" && pwd -P)"
  original_cwd="$(pwd -P)"
  project_hash="$(draccus_hash_path "$project_root")"
  project_id="$(draccus_slug "$project_name")-$project_hash"

  if [[ "$no_record" -eq 1 ]]; then
    DRACCUS_WORKSPACE="$project_root" draccus_runtime_exec_run "$@"
    return $?
  fi

  local runs_dir_cfg runs_project_dir run_id run_id_base run_dir run_suffix=1 started_at finished_at rc mkdir_error
  if [[ -z "$runs_dir" ]]; then
    if runs_dir_cfg="$(draccus_project_runs_dir_from_config "$config" 2>/dev/null)"; then
      runs_dir="$runs_dir_cfg"
    else
      runs_dir="$(draccus_runs_root)"
    fi
  fi
  runs_dir="$(_draccus_run_resolve_runs_dir "$project_root" "$runs_dir")"

  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run_id_base="$(draccus_timestamp_utc)"
  if [[ -n "$name" ]]; then
    run_id_base="$run_id_base-$(draccus_slug "$name")"
  fi

  runs_project_dir="$runs_dir/$project_id"
  if ! mkdir -p "$runs_project_dir"; then
    echo "draccus: error: failed to create runs directory: $runs_project_dir" >&2
    return 1
  fi

  run_id="$run_id_base"
  run_dir="$runs_project_dir/$run_id"
  while ! mkdir_error="$(mkdir "$run_dir" 2>&1)"; do
    if [[ ! -e "$run_dir" ]]; then
      [[ -z "$mkdir_error" ]] || echo "$mkdir_error" >&2
      echo "draccus: error: failed to create run directory: $run_dir" >&2
      return 1
    fi
    run_suffix=$((run_suffix + 1))
    run_id="$run_id_base-$run_suffix"
    run_dir="$runs_project_dir/$run_id"
  done

  mkdir "$run_dir/logs"
  _draccus_run_write_start_record \
    "$run_dir" \
    "$run_id" \
    "$started_at" \
    "$original_cwd" \
    "$project_root" \
    "$project_name" \
    "$project_id" \
    "$bundle_path" \
    "$@"

  set +e
  (DRACCUS_WORKSPACE="$project_root" draccus_runtime_exec_run "$@") \
    > >(tee "$run_dir/logs/stdout.log") \
    2> >(tee "$run_dir/logs/stderr.log" >&2)
  rc=$?
  set -e

  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _draccus_run_write_result_record "$run_dir" "$run_id" "$finished_at" "$rc"
  echo "draccus run: record written to $run_dir" >&2
  return "$rc"
}
