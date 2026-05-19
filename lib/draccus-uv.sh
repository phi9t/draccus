# shellcheck shell=bash
# Draccus uv wrapper logic.
# Source this file from bin/draccus-uv; do not execute directly.

# shellcheck source=draccus-project.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-project.sh"

draccus_uv_has_explicit_pip_target() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --python | --python=* | --system | --target | --target=* | --prefix | --prefix=*)
        return 0
        ;;
    esac
  done
  return 1
}

draccus_uv_requirement_name() {
  local spec="$1"
  spec="${spec%%#*}"
  spec="${spec%%;*}"
  spec="${spec#"${spec%%[![:space:]]*}"}"
  spec="${spec%"${spec##*[![:space:]]}"}"
  spec="${spec,,}"
  spec="${spec%%\[*}"
  spec="${spec%%==*}"
  spec="${spec%%!=*}"
  spec="${spec%%<=*}"
  spec="${spec%%>=*}"
  spec="${spec%%<*}"
  spec="${spec%%>*}"
  spec="${spec%%~=*}"
  printf '%s\n' "$spec"
}

draccus_uv_forbidden_requirement_p() {
  local name
  name="$(draccus_uv_requirement_name "$1")"
  case "$name" in
    torch | jax | jaxlib | numpy | scipy | triton | nvidia-*)
      printf '%s\n' "$name"
      return 0
      ;;
  esac
  return 1
}

draccus_uv_check_requirement_file() {
  local reqfile="$1"
  local line forbidden

  [[ -f "$reqfile" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "" | "#"* | "-"*)
        continue
        ;;
    esac
    if forbidden="$(draccus_uv_forbidden_requirement_p "$line")"; then
      echo "draccus-uv: refusing to install foundation package '$forbidden' from $reqfile; it must resolve from /opt/draccus/view/base-ml" >&2
      return 2
    fi
  done <"$reqfile"
}

draccus_uv_reject_forbidden_installs() {
  local arg forbidden expect_file=0 skip_next=0

  for arg in "$@"; do
    if ((expect_file)); then
      draccus_uv_check_requirement_file "$arg"
      expect_file=0
      continue
    fi
    if ((skip_next)); then
      skip_next=0
      continue
    fi

    case "$arg" in
      -r | --requirement)
        expect_file=1
        continue
        ;;
      -r*)
        draccus_uv_check_requirement_file "${arg#-r}"
        continue
        ;;
      --requirement=*)
        draccus_uv_check_requirement_file "${arg#*=}"
        continue
        ;;
      -c | --constraint | --override | -e | --editable | --find-links | -f | --index-url | --extra-index-url)
        skip_next=1
        continue
        ;;
      -* | . | /*)
        continue
        ;;
    esac

    if forbidden="$(draccus_uv_forbidden_requirement_p "$arg")"; then
      echo "draccus-uv: refusing to install foundation package '$forbidden'; it must resolve from /opt/draccus/view/base-ml" >&2
      return 2
    fi
  done
}

draccus_uv_audit_pip_plan() {
  local pip_cmd="$1"
  shift
  local plan line installed forbidden

  if ! plan="$("$DRACCUS_BUNDLE/bin/draccus-run" uv pip "$pip_cmd" --dry-run "$@" 2>&1)"; then
    printf '%s\n' "$plan" >&2
    return 2
  fi

  while IFS= read -r line; do
    case "$line" in
      " + "*)
        installed="${line# + }"
        installed="${installed%%==*}"
        if forbidden="$(draccus_uv_forbidden_requirement_p "$installed")"; then
          echo "draccus-uv: refusing install plan because it would add foundation package '$forbidden'; it must resolve from /opt/draccus/view/base-ml" >&2
          return 2
        fi
        ;;
    esac
  done <<<"$plan"
}

draccus_uv_ensure_workspace_venv() {
  if [[ ! -f ".venv/pyvenv.cfg" ]]; then
    "$DRACCUS_BUNDLE/bin/draccus-run" bash -lc 'uv venv --python "$(which python)" --system-site-packages /workspace/.venv'
  fi
  draccus_project_neutralize_pip "$PWD/.venv"
}

draccus_uv_neutralize_created_venvs() {
  local candidate last_arg

  if [[ -f ".venv/pyvenv.cfg" ]]; then
    draccus_project_neutralize_pip "$PWD/.venv"
  fi

  if (($# > 0)); then
    last_arg="${!#}"
    case "$last_arg" in
      -*)
        return 0
        ;;
    esac
    candidate="$last_arg"
    [[ "$candidate" = /* ]] || candidate="$PWD/$candidate"
    if [[ -f "$candidate/pyvenv.cfg" ]]; then
      draccus_project_neutralize_pip "$candidate"
    fi
  fi
}

draccus_uv_main() {
  local cmd="${1:-}"
  local pip_cmd="${2:-}"

  case "$cmd:$pip_cmd" in
    pip:install | pip:sync | pip:uninstall)
      shift 2
      if [[ "$pip_cmd" != "uninstall" ]]; then
        draccus_uv_reject_forbidden_installs "$@"
      fi
      if draccus_uv_has_explicit_pip_target "$@"; then
        if [[ "$pip_cmd" != "uninstall" ]]; then
          draccus_uv_audit_pip_plan "$pip_cmd" "$@"
        fi
        exec "$DRACCUS_BUNDLE/bin/draccus-run" uv pip "$pip_cmd" "$@"
      fi
      draccus_uv_ensure_workspace_venv
      if [[ "$pip_cmd" != "uninstall" ]]; then
        draccus_uv_audit_pip_plan "$pip_cmd" --python /workspace/.venv/bin/python "$@"
      fi
      exec "$DRACCUS_BUNDLE/bin/draccus-run" uv pip "$pip_cmd" --python /workspace/.venv/bin/python "$@"
      ;;
  esac

  if [[ "$cmd" == "venv" ]]; then
    "$DRACCUS_BUNDLE/bin/draccus-run" uv "$@"
    draccus_uv_neutralize_created_venvs "$@"
    return 0
  fi

  exec "$DRACCUS_BUNDLE/bin/draccus-run" uv "$@"
}
