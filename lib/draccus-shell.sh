# shellcheck shell=bash
# Draccus native interactive shell logic.
# Source this file; do not execute directly.

draccus_shell_ensure_starship() {
  # shellcheck source=../scripts/starship-version.env
  source "$DRACCUS_BUNDLE/scripts/starship-version.env"

  local target="$DRACCUS_CACHE/starship/bin/starship"
  local tmpdir archive

  if [[ -x "$target" ]] && "$target" --version 2>/dev/null | grep -qF "starship ${STARSHIP_VERSION#v}"; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
    echo "draccus-shell: starship bootstrap skipped: curl, tar, and sha256sum are required" >&2
    return 0
  fi

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/draccus-starship.XXXXXX")"
  archive="$tmpdir/starship.tar.gz"
  trap 'rm -rf "$tmpdir"' RETURN

  curl -fsSL "$STARSHIP_URL" -o "$archive"
  printf '%s  %s\n' "$STARSHIP_SHA256" "$archive" | sha256sum -c >/dev/null
  tar -xzf "$archive" -C "$tmpdir" starship

  mkdir -p "$DRACCUS_CACHE/starship/bin"
  install -m 0755 "$tmpdir/starship" "$target"
}

draccus_shell_write_zdotdir() {
  local zdotdir="$DRACCUS_CACHE/draccus-shell/zsh"
  mkdir -p "$zdotdir"

  cat >"$zdotdir/.zshenv" <<'EOF'
source /opt/draccus/cache/draccus-shell/zsh/init.zsh
EOF

  cat >"$zdotdir/init.zsh" <<'EOF'
export VIRTUAL_ENV_DISABLE_PROMPT=1

if [[ -f /opt/draccus/spack/share/spack/setup-env.sh ]]; then
  source /opt/draccus/spack/share/spack/setup-env.sh
  if (( $+functions[spack] && ! $+functions[_draccus_spack_upstream] )); then
    functions[_draccus_spack_upstream]=$functions[spack]
    spack() {
      if [[ "${1:-}" == "env" && "${2:-}" == "activate" ]]; then
        local -a args
        local idx env_name env_path
        args=("$@")
        for (( idx = ${#args[@]}; idx >= 3; idx-- )); do
          case "${args[$idx]}" in
            -*)
              continue
              ;;
          esac
          env_name="${args[$idx]}"
          env_path="/opt/draccus/cache/spack-readonly-envs/$env_name"
          if [[ "$env_name" != */* && -d "$env_path" ]]; then
            args[$idx]="$env_path"
          fi
          break
        done
        _draccus_spack_upstream "${args[@]}" || return $?
        if [[ -n "${VIRTUAL_ENV:-}" && -f "$VIRTUAL_ENV/bin/activate" ]]; then
          source "$VIRTUAL_ENV/bin/activate"
        fi
        return 0
      fi
      _draccus_spack_upstream "$@"
    }
  fi
fi

if [[ -z "${SPACK_ENV:-}" && -d /opt/draccus/cache/spack-readonly-envs/base-ml ]]; then
  spack env activate base-ml >/dev/null 2>&1 || true
fi

if [[ -f /workspace/.venv/bin/activate ]]; then
  source /workspace/.venv/bin/activate
fi

export STARSHIP_CONFIG=/opt/draccus/cache/draccus-shell/starship.toml

if [[ -o interactive ]]; then
  if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
  else
    setopt prompt_subst
    PROMPT='[spack:${SPACK_ENV:t:-none}] [uv:${VIRTUAL_ENV:t:-none}] %~ %# '
  fi
fi
EOF

  cat >"$DRACCUS_CACHE/draccus-shell/starship.toml" <<'EOF'
add_newline = false
format = "${custom.draccus_spack}${custom.draccus_uv}$directory$character"

[custom.draccus_spack]
command = "basename \"${SPACK_ENV:-none}\""
when = "test -n \"${SPACK_ENV:-}\""
style = "blue"
format = "[spack:$output]($style) "

[custom.draccus_uv]
command = "basename \"${VIRTUAL_ENV:-none}\""
when = "test -n \"${VIRTUAL_ENV:-}\""
style = "green"
format = "[uv:$output]($style) "

[directory]
truncation_length = 1
truncate_to_repo = false
home_symbol = "~"
read_only = ""

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"
EOF
}

draccus_shell_main() {
  local bundle_override=""
  local selected_bundle

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "draccus shell: --bundle requires a path" >&2
          return 2
        fi
        bundle_override="$1"
        shift
        ;;
      *)
        echo "draccus shell is interactive-only; use draccus run inside a project for commands" >&2
        return 2
        ;;
    esac
  done

  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "draccus shell is interactive-only; stdin and stdout must be terminals. Use draccus run inside a project for commands." >&2
    return 2
  fi

  if [[ -n "$bundle_override" ]]; then
    if [[ ! -d "$bundle_override" ]]; then
      echo "draccus shell: selected bundle does not exist: $bundle_override" >&2
      return 2
    fi
    selected_bundle="$(cd "$bundle_override" && pwd)"
    DRACCUS_BUNDLE="$selected_bundle"
    export DRACCUS_BUNDLE
    unset DRACCUS_ROOTFS DRACCUS_STATE DRACCUS_CACHE DRACCUS_BUILD
  fi

  DRACCUS_CACHE="${DRACCUS_CACHE:-$DRACCUS_BUNDLE/cache}"
  export DRACCUS_CACHE

  # shellcheck source=draccus-runtime.sh
  source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

  draccus_shell_ensure_starship
  draccus_shell_write_zdotdir

  draccus_runtime_exec_run \
    env ZDOTDIR=/opt/draccus/cache/draccus-shell/zsh \
    SHELL=/opt/draccus/view/base-sys/bin/zsh \
    zsh
}
