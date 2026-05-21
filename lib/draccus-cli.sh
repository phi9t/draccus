#!/usr/bin/env bash

draccus_die() {
  echo "draccus: $*" >&2
  exit 2
}

draccus_usage() {
  cat <<'EOF'
Usage:
  draccus shell [--bundle PATH]
  draccus run [--name NAME] [--no-record] [--runs-dir DIR] -- <cmd> [args...]
  draccus uv <uv-args...>
  draccus doctor [--json]
  draccus notebook [--port PORT] [--host HOST]
  draccus build -- <cmd> [args...]
  draccus project init <name> [--path PATH]
  draccus bundle show [--json]
  draccus help [subcommand]
EOF
}

draccus_help_shell() {
  cat <<'EOF'
Usage:
  draccus shell [--bundle PATH]

Open an interactive Draccus ML shell.
EOF
}

draccus_help_run() {
  cat <<'EOF'
Usage:
  draccus run [--name NAME] [--no-record] [--runs-dir DIR] -- <cmd> [args...]

Run a project command inside Draccus. Recording support is not implemented yet.
EOF
}

draccus_help_uv() {
  cat <<'EOF'
Usage:
  draccus uv <uv-args...>

Manage project Python packages with Draccus layering protections.
EOF
}

draccus_help_doctor() {
  cat <<'EOF'
Usage:
  draccus doctor [--json]

Check the Draccus bundle, runtime, and GPU environment.
EOF
}

draccus_help_notebook() {
  cat <<'EOF'
Usage:
  draccus notebook [--port PORT] [--host HOST]

Launch a project notebook server inside Draccus.
EOF
}

draccus_help_build() {
  cat <<'EOF'
Usage:
  draccus build -- <cmd> [args...]

Run a mutating foundation build command inside the writable Draccus bundle.
EOF
}

draccus_help_project() {
  cat <<'EOF'
Usage:
  draccus project init <name> [--path PATH]

Create a Draccus project.
EOF
}

draccus_help_bundle() {
  cat <<'EOF'
Usage:
  draccus bundle show [--json]

Show the active Draccus bundle.
EOF
}

draccus_help() {
  local topic="${1:-}"

  case "$topic" in
    "")
      draccus_usage
      ;;
    shell)
      draccus_help_shell
      ;;
    run)
      draccus_help_run
      ;;
    uv)
      draccus_help_uv
      ;;
    doctor)
      draccus_help_doctor
      ;;
    notebook)
      draccus_help_notebook
      ;;
    build)
      draccus_help_build
      ;;
    project)
      draccus_help_project
      ;;
    bundle)
      draccus_help_bundle
      ;;
    help)
      draccus_usage
      ;;
    *)
      draccus_die "unknown help topic: $topic"
      ;;
  esac
}

draccus_dispatch() {
  local command="${1:-}"

  case "$command" in
    "" | --help | -h)
      draccus_help
      ;;
    help)
      shift
      case "${1:-}" in
        "" | --help | -h)
          draccus_help
          ;;
        *)
          draccus_help "$1"
          ;;
      esac
      ;;
    build)
      shift
      if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        draccus_help "$command"
        return 0
      fi
      if [[ "${1:-}" == "--" ]]; then
        shift
      fi
      if [[ $# -eq 0 ]]; then
        draccus_die "build requires a command; usage: draccus build -- <cmd> [args...]"
      fi
      # shellcheck source=draccus-runtime.sh
      source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"
      draccus_runtime_exec_build "$@"
      ;;
    shell | run | uv | doctor | notebook | project | bundle)
      if [[ "${2:-}" == "--help" || "${2:-}" == "-h" ]]; then
        draccus_help "$command"
        return 0
      fi
      draccus_die "subcommand '$command' is not implemented yet; try 'draccus help $command'"
      ;;
    *)
      draccus_die "unknown subcommand: $command"
      ;;
  esac
}
