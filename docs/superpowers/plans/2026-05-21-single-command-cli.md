# Single Command CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy per-command public surface with one polished `bin/draccus` command, including recorded project runs and full validation/docs updates.

**Architecture:** Keep the first CLI Bash-based. `bin/draccus` is a thin dispatcher; reusable runtime, project, uv, doctor, shell, and run-record logic lives in focused `lib/draccus-*.sh` files so a future Rust CLI can replace only the router. Preserve the existing runtime namespace contract by mechanically moving current launcher behavior into library functions before deleting old entrypoints.

**Tech Stack:** Bash, bubblewrap, Spack, uv, existing `scripts/validate-static.sh` Gate 0, Markdown docs, org-mode workstream tracker.

---

## File Structure

Create or modify these files:

- Create `bin/draccus`: single public CLI dispatcher.
- Create `lib/draccus-cli.sh`: help, dispatch, common error/usage helpers.
- Create `lib/draccus-layout.sh`: `~/.automata/draccus` layout, default bundle resolution, project id/run id helpers.
- Create `lib/draccus-runtime.sh`: runtime/build namespace entry functions shared by `draccus run` and `draccus build`.
- Create `lib/draccus-shell.sh`: current zsh/starship shell behavior as a function.
- Modify `lib/draccus-project.sh`: current project helpers plus `draccus.yaml` discovery/schema helpers.
- Modify `lib/draccus-uv.sh`: use the runtime library instead of a removed legacy public launcher.
- Create `lib/draccus-run-record.sh`: operational run directory creation and live tee logging.
- Create `lib/draccus-doctor.sh`: user-facing health checks and `--json`.
- Create `lib/draccus-notebook.sh`: project-bound Jupyter launch wrapper.
- Modify `scripts/validate-static.sh`: enforce the single public command and shellcheck/shfmt new libs.
- Modify `scripts/validate-all.sh`: replace legacy command invocations with `bin/draccus`.
- Modify `projects/_template/README.md`: new CLI examples only.
- Create `projects/_template/draccus.yaml`: template project metadata.
- Modify `README.md`, `DESIGN.md`, `docs/training-substrate-roadmap.md`, `docs/tech-blog-hello-draccus.md`: new command surface only.
- Modify `.workstream/single-command-cli/tracker.org`: claim and complete tasks as implementation proceeds.
- Remove the legacy public files for run, build, shell, uv, probe, project init, debug shell, and offline behavior in the final migration task. Task 8 completed that removal; do not recreate shims.

Do not touch `envs/*/spack.yaml`, `scripts/validate_uv_layering.sh` `DO_NOT_SHADOW`, or pinned CUDA/Torch/JAX versions.

---

### Task 1: Workstream Preflight And Decisions

**Files:**
- Modify: `.workstream/single-command-cli/tracker.org`
- Create artifacts under `.workstream/single-command-cli/artifacts/`

- [ ] **Step 1: Claim P0.1 in the tracker**

Update `.workstream/single-command-cli/tracker.org` P0.1 from `TODO` to `IN-PROGRESS`, set `:OWNER:` to your agent/session name, and set `:STARTED:` to current UTC ISO timestamp.

- [ ] **Step 2: Capture current CLI baseline**

Run:

```bash
find bin -maxdepth 1 -type f -printf '%f\n' | sort \
  | tee .workstream/single-command-cli/artifacts/p0.1-bin-before.txt
rg -n "legacy public Draccus command names" README.md DESIGN.md docs scripts projects .workstream \
  | tee .workstream/single-command-cli/artifacts/p0.1-legacy-refs-before.txt
./scripts/validate-static.sh 2>&1 \
  | tee .workstream/single-command-cli/artifacts/p0.1-validate-static-before.log
```

Expected:

- `p0.1-bin-before.txt` lists the existing legacy entrypoints.
- `validate-static-before.log` ends with `RESULT: SUCCESS`.

- [ ] **Step 3: Mark P0.1 DONE**

Update P0.1 to `DONE`, set `:FINISHED:`, and add an `** Artifacts` block listing the three artifacts from Step 2.

- [ ] **Step 4: Fill tracker decisions**

Update `.workstream/single-command-cli/tracker.org` decisions exactly:

```org
:DECIDED_BY: user-approved spec
:DECIDED_ON: output of `date -u +%Y-%m-%dT%H:%M:%SZ`
```

Keep the existing choices:

- command grammar includes `shell`, `run`, `uv`, `doctor`, `notebook`, `build`, `project init`, `bundle show`, and `help`
- `draccus.yaml` schema v1 has `name`, optional `bundle`, optional `runs_dir`
- project id is `<name>-<hash>`
- shared root is `~/.automata/draccus`
- legacy entrypoints are removed, not shimmed

- [ ] **Step 5: Commit preflight tracker changes**

Run:

```bash
git add .workstream/single-command-cli/tracker.org .workstream/single-command-cli/artifacts
git commit -m "Track single-command CLI preflight"
```

Expected: commit succeeds. If the artifacts are too noisy, keep only small text/log summaries and note omitted large logs in the tracker.

---

### Task 2: Add Thin `bin/draccus` Dispatcher And Help

**Files:**
- Create: `bin/draccus`
- Create: `lib/draccus-cli.sh`
- Modify: `scripts/validate-static.sh`
- Modify: `.workstream/single-command-cli/tracker.org`

- [ ] **Step 1: Add failing static checks for the new dispatcher**

Modify `scripts/validate-static.sh`:

1. Add to `SHELL_FILES`:

```bash
"$DRACCUS_BUNDLE/bin/draccus"
"$DRACCUS_BUNDLE/lib/draccus-cli.sh"
```

2. Add to launcher executability checks before the legacy launcher list:

```bash
check "executable: draccus" "test -x \"$DRACCUS_BUNDLE/bin/draccus\""
```

3. Add a new command-surface check near Check 8:

```bash
check "draccus help mentions shell" "\"$DRACCUS_BUNDLE/bin/draccus\" --help | grep -qF 'draccus shell'"
check "draccus help mentions run" "\"$DRACCUS_BUNDLE/bin/draccus\" --help | grep -qF 'draccus run'"
```

- [ ] **Step 2: Run Gate 0 and verify it fails for missing files**

Run:

```bash
./scripts/validate-static.sh
```

Expected: fails on missing/non-executable `bin/draccus` or missing help output.

- [ ] **Step 3: Create `lib/draccus-cli.sh`**

Create `lib/draccus-cli.sh`:

```bash
# shellcheck shell=bash

draccus_die() {
  echo "draccus: error: $*" >&2
  exit 1
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

Draccus provides a shared ML foundation under /opt/draccus, project uv overlays,
and recorded project runs. Use "draccus help <subcommand>" for details.
EOF
}

draccus_help_shell() {
  cat <<'EOF'
Usage:
  draccus shell [--bundle PATH]

Open a native interactive Draccus shell. This works outside a project, uses the
default bundle unless --bundle is supplied, and does not create a run record.
EOF
}

draccus_help_run() {
  cat <<'EOF'
Usage:
  draccus run [--name NAME] [--no-record] [--runs-dir DIR] -- <cmd> [args...]

Run a project command inside Draccus. A draccus.yaml project is required.
By default, stdout/stderr stream live and are also written to a run directory.
EOF
}

draccus_help_uv() {
  cat <<'EOF'
Usage:
  draccus uv <uv-args...>

Run uv for the current Draccus project. Mutating commands target the project
.venv and keep foundation packages such as torch, jax, numpy, and scipy owned by
the shared foundation.
EOF
}

draccus_help_doctor() {
  cat <<'EOF'
Usage:
  draccus doctor [--json]

Check the selected Draccus bundle, namespace contract, GPU visibility, uv/pip
shim behavior, and foundation package provenance.
EOF
}

draccus_help_notebook() {
  cat <<'EOF'
Usage:
  draccus notebook [--port PORT] [--host HOST]

Launch JupyterLab from the current Draccus project. If JupyterLab is missing,
install it with: draccus uv pip install jupyterlab
EOF
}

draccus_help_build() {
  cat <<'EOF'
Usage:
  draccus build -- <cmd> [args...]

Run a command in the writable foundation-maintenance namespace. This can mutate
Spack state and should not be used for normal research commands.
EOF
}

draccus_help_project() {
  cat <<'EOF'
Usage:
  draccus project init <name> [--path PATH]

Create or initialize a Draccus model project with draccus.yaml, pyproject.toml,
.venv, uv.lock, and disabled pip stubs.
EOF
}

draccus_help_bundle() {
  cat <<'EOF'
Usage:
  draccus bundle show [--json]

Show the selected/default Draccus bundle. Later workstreams add pack/unpack.
EOF
}

draccus_help() {
  case "${1:-}" in
    "" | -h | --help) draccus_usage ;;
    shell) draccus_help_shell ;;
    run) draccus_help_run ;;
    uv) draccus_help_uv ;;
    doctor) draccus_help_doctor ;;
    notebook) draccus_help_notebook ;;
    build) draccus_help_build ;;
    project) draccus_help_project ;;
    bundle) draccus_help_bundle ;;
    *) draccus_die "unknown help topic '$1'" ;;
  esac
}

draccus_dispatch() {
  local cmd="${1:-help}"
  case "$cmd" in
    -h | --help | help)
      shift || true
      draccus_help "${1:-}"
      ;;
    *)
      draccus_die "subcommand '$cmd' is not implemented yet; see .workstream/single-command-cli"
      ;;
  esac
}
```

- [ ] **Step 4: Create `bin/draccus`**

Create `bin/draccus`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/draccus-env.sh"
# shellcheck source=../lib/draccus-cli.sh
source "$DRACCUS_BUNDLE/lib/draccus-cli.sh"

draccus_dispatch "$@"
```

Make it executable:

```bash
chmod +x bin/draccus
```

- [ ] **Step 5: Verify help and Gate 0**

Run:

```bash
./bin/draccus --help
./bin/draccus help run
./scripts/validate-static.sh
```

Expected:

- Help includes `draccus shell` and `draccus run`.
- Gate 0 passes.

- [ ] **Step 6: Commit**

```bash
git add bin/draccus lib/draccus-cli.sh scripts/validate-static.sh .workstream/single-command-cli/tracker.org
git commit -m "Add draccus command dispatcher"
```

---

### Task 3: Extract Runtime And Build Entry Logic Into `lib/draccus-runtime.sh`

**Files:**
- Create: `lib/draccus-runtime.sh`
- Modify: `bin/draccus`
- Modify: `lib/draccus-cli.sh`
- Modify: `scripts/validate-static.sh`

- [ ] **Step 1: Add runtime library to static validation**

Add `"$DRACCUS_BUNDLE/lib/draccus-runtime.sh"` to `SHELL_FILES` in `scripts/validate-static.sh`.

- [ ] **Step 2: Create runtime library shell**

Create `lib/draccus-runtime.sh`:

```bash
# shellcheck shell=bash

# shellcheck source=draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-env.sh"

draccus_runtime_exec_run() {
  DRACCUS_RUNTIME_MODE=run draccus_runtime_exec "$@"
}

draccus_runtime_exec_build() {
  DRACCUS_RUNTIME_MODE=build draccus_runtime_exec "$@"
}

draccus_runtime_exec() {
  local mode="${DRACCUS_RUNTIME_MODE:-run}"
  case "$mode" in
    run | build) ;;
    *) echo "draccus-runtime: invalid mode '$mode'" >&2; return 2 ;;
  esac

  # Move the run/build bwrap setup into
  # this function. Keep the run/build branch limited to bind mode and env/PATH
  # differences. Preserve all existing mount paths and env vars.
  #
  # Implementation rule:
  # - run mode must keep state/spack, state/view, envs, shims, and host-bin
  #   read-only exactly as the run-mode contract requires.
  # - build mode must keep state/spack, state/view, envs writable exactly as
  #   the build-mode contract requires.
  # - both modes must preserve DRACCUS_WORKSPACE defaulting to $PWD.
  :
}
```

- [ ] **Step 3: Mechanically move existing launcher bodies into the function**

Edit `lib/draccus-runtime.sh` by moving the run/build namespace bodies into `draccus_runtime_exec`.

Use these concrete branch points:

```bash
local rootfs state cache build workspace
rootfs="${DRACCUS_ROOTFS:-$DRACCUS_BUNDLE/rootfs}"
state="${DRACCUS_STATE:-$DRACCUS_BUNDLE/state}"
cache="${DRACCUS_CACHE:-$DRACCUS_BUNDLE/cache}"
build="${DRACCUS_BUILD:-$DRACCUS_BUNDLE/build}"
workspace="${DRACCUS_WORKSPACE:-$PWD}"
```

For run-mode bind arrays:

```bash
draccus_foundation_bind_args=(
  --ro-bind "$DRACCUS_BUNDLE/host-bin" /opt/draccus/host-bin
  --ro-bind "$DRACCUS_BUNDLE/shims" /opt/draccus/shims
  --ro-bind "$DRACCUS_BUNDLE/envs" /opt/draccus/envs
  --ro-bind "$state/spack" /opt/draccus/spack
  --ro-bind "$state/view" /opt/draccus/view
)
```

For build-mode bind arrays:

```bash
draccus_foundation_bind_args=(
  --bind "$DRACCUS_BUNDLE/envs" /opt/draccus/envs
  --bind "$state/spack" /opt/draccus/spack
  --bind "$state/view" /opt/draccus/view
)
```

Keep `uv_overrides_args` only in run mode.

- [ ] **Step 4: Route through the single dispatcher**

Wire `bin/draccus` to call `draccus_runtime_exec_run` for `draccus run` and
`draccus_runtime_exec_build` for `draccus build`. Earlier implementation notes
used temporary compatibility wrappers during migration; Task 8 removed those
files. Do not recreate them.

- [ ] **Step 5: Add `draccus build` dispatch**

In `lib/draccus-cli.sh`, source runtime library lazily inside the `build` case:

```bash
build)
  shift
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || draccus_die "build requires a command after --"
  # shellcheck source=draccus-runtime.sh
  source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"
  draccus_runtime_exec_build "$@"
  ;;
```

- [ ] **Step 6: Verify run and build subcommands**

Run:

```bash
./bin/draccus run -- bash -lc 'test "$DRACCUS_PREFIX" = /opt/draccus'
./bin/draccus build -- bash -lc 'test "$DRACCUS_PREFIX" = /opt/draccus'
./bin/draccus build -- bash -lc 'test "$SPACK_ROOT" = /opt/draccus/spack'
./scripts/validate-static.sh
```

Expected: all commands exit 0 and Gate 0 passes.

- [ ] **Step 7: Commit**

```bash
git add bin/draccus lib/draccus-runtime.sh lib/draccus-cli.sh scripts/validate-static.sh
git commit -m "Extract Draccus runtime launcher logic"
```

---

### Task 4: Add Shared Layout And Project Config Helpers

**Files:**
- Create: `lib/draccus-layout.sh`
- Modify: `lib/draccus-project.sh`
- Modify: `lib/draccus-cli.sh`
- Modify: `scripts/validate-static.sh`

- [ ] **Step 1: Add new libs to static validation**

Add to `SHELL_FILES`:

```bash
"$DRACCUS_BUNDLE/lib/draccus-layout.sh"
```

- [ ] **Step 2: Create layout helper**

Create `lib/draccus-layout.sh`:

```bash
# shellcheck shell=bash

draccus_home() {
  printf '%s\n' "${DRACCUS_HOME:-$HOME/.automata/draccus}"
}

draccus_default_bundle() {
  printf '%s\n' "${DRACCUS_DEFAULT_BUNDLE:-$(draccus_home)/bundles/default}"
}

draccus_runs_root() {
  printf '%s\n' "${DRACCUS_RUNS_ROOT:-$(draccus_home)/runs}"
}

draccus_managed_projects_root() {
  printf '%s\n' "${DRACCUS_PROJECTS_ROOT:-$(draccus_home)/projects}"
}

draccus_hash_path() {
  local path="$1"
  printf '%s' "$path" | sha256sum | awk '{print substr($1,1,12)}'
}

draccus_slug() {
  local value="$1"
  value="${value,,}"
  value="${value//[^a-z0-9._-]/-}"
  value="${value##[-.]}"
  value="${value%%[-.]}"
  [[ -n "$value" ]] || value="project"
  printf '%s\n' "$value"
}

draccus_timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}
```

- [ ] **Step 3: Add `draccus.yaml` helpers to `lib/draccus-project.sh`**

Append these functions:

```bash
draccus_project_config_path() {
  local dir parent
  dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/draccus.yaml" ]]; then
      printf '%s\n' "$dir/draccus.yaml"
      return 0
    fi
    parent="$(dirname "$dir")"
    dir="$parent"
  done
  return 1
}

draccus_project_root_from_config() {
  local config
  config="$(draccus_project_config_path)" || return 1
  dirname "$config"
}

draccus_yaml_value() {
  local key="$1" file="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":" {
      sub("^[[:space:]]*" key ":[[:space:]]*", "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      print
      exit
    }
  ' "$file"
}

draccus_project_name_from_config() {
  local config name
  config="$(draccus_project_config_path)" || return 1
  name="$(draccus_yaml_value name "$config")"
  [[ -n "$name" ]] || return 1
  printf '%s\n' "$name"
}

draccus_project_bundle_from_config() {
  local config bundle
  config="$(draccus_project_config_path)" || return 1
  bundle="$(draccus_yaml_value bundle "$config")"
  [[ -n "$bundle" ]] || return 1
  printf '%s\n' "$bundle"
}

draccus_project_runs_dir_from_config() {
  local config runs_dir
  config="$(draccus_project_config_path)" || return 1
  runs_dir="$(draccus_yaml_value runs_dir "$config")"
  [[ -n "$runs_dir" ]] || return 1
  printf '%s\n' "$runs_dir"
}

draccus_project_assert_config() {
  if ! draccus_project_config_path >/dev/null 2>&1; then
    echo "draccus: error: no draccus.yaml found. Run: draccus project init <name>" >&2
    exit 1
  fi
}
```

- [ ] **Step 4: Verify syntax and Gate 0**

Run:

```bash
bash -n lib/draccus-layout.sh lib/draccus-project.sh
./scripts/validate-static.sh
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add lib/draccus-layout.sh lib/draccus-project.sh scripts/validate-static.sh
git commit -m "Add Draccus project config helpers"
```

---

### Task 5: Implement `draccus project init`

**Files:**
- Modify: `lib/draccus-project.sh`
- Modify: `lib/draccus-cli.sh`
- Modify: `projects/_template/pyproject.toml`
- Modify: `projects/_template/README.md`
- Create: `projects/_template/draccus.yaml`

- [ ] **Step 1: Add template `draccus.yaml`**

Create `projects/_template/draccus.yaml`:

```yaml
name: REPLACE_ME
# bundle: /absolute/path/to/shared/draccus/bundle
# runs_dir: /absolute/path/to/run/artifacts
```

- [ ] **Step 2: Update template README command examples**

Replace old examples in `projects/_template/README.md` with:

```markdown
# Project REPLACE_ME

## Quickstart

```bash
draccus uv sync --frozen
draccus run --name foundation-smoke -- python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
draccus shell
```

## Adding dependencies

```bash
draccus uv pip install transformers datasets accelerate
draccus uv sync
```

## Foundation packages

The shared Draccus foundation owns torch, jax, jaxlib, numpy, scipy, triton, and
all nvidia-* packages. Do not add those packages to project dependencies.
```
```

- [ ] **Step 3: Add project init function**

Add `draccus_project_init_main` to `lib/draccus-project.sh`:

```bash
draccus_project_init_main() {
  local name="" path="" root git_root py_ver
  [[ "${1:-}" == "init" ]] && shift
  [[ $# -ge 1 ]] || { echo "draccus project init: missing <name>" >&2; return 2; }
  name="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        path="${2:-}"
        [[ -n "$path" ]] || { echo "draccus project init: --path requires a value" >&2; return 2; }
        shift 2
        ;;
      *)
        echo "draccus project init: unknown argument '$1'" >&2
        return 2
        ;;
    esac
  done

  if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "draccus project init: name must be lowercase alphanumeric + hyphens" >&2
    return 2
  fi
  if [[ "$name" == nvidia-* ]]; then
    echo "draccus project init: names starting with nvidia- are forbidden" >&2
    return 2
  fi

  if [[ -n "$path" ]]; then
    root="$path"
  elif git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    root="$git_root"
  else
    # shellcheck source=draccus-layout.sh
    source "$DRACCUS_BUNDLE/lib/draccus-layout.sh"
    root="$(draccus_managed_projects_root)/$name"
  fi

  mkdir -p "$root"
  if [[ ! -f "$root/pyproject.toml" ]]; then
    cp "$DRACCUS_BUNDLE/projects/_template/pyproject.toml" "$root/pyproject.toml"
  fi
  if [[ ! -f "$root/.gitignore" ]]; then
    cp "$DRACCUS_BUNDLE/projects/_template/.gitignore" "$root/.gitignore"
  fi
  sed -i "s/REPLACE_ME/$name/g" "$root/pyproject.toml"
  cat >"$root/draccus.yaml" <<EOF
name: $name
# bundle: /absolute/path/to/shared/draccus/bundle
# runs_dir: /absolute/path/to/run/artifacts
EOF

  DRACCUS_WORKSPACE="$root" draccus_runtime_exec_run bash -lc '
    set -euo pipefail
    py_ver=$(python -c "import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")")
    printf "%s\n" "$py_ver" >/workspace/.python-version
    sed -i "s/requires-python = .*/requires-python = \">=$py_ver\"/" /workspace/pyproject.toml
    uv venv --python "$(which python)" --system-site-packages /workspace/.venv
    cd /workspace && uv lock
  '
  draccus_project_neutralize_pip "$root/.venv"
  echo "Initialized Draccus project at $root"
}
```

At the top of `lib/draccus-project.sh`, source runtime when needed:

```bash
# shellcheck source=draccus-runtime.sh
source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"
```

- [ ] **Step 4: Dispatch `draccus project init`**

In `lib/draccus-cli.sh`, add:

```bash
project)
  shift
  [[ "${1:-}" == "init" ]] || draccus_die "expected: draccus project init <name> [--path PATH]"
  # shellcheck source=draccus-project.sh
  source "$DRACCUS_BUNDLE/lib/draccus-project.sh"
  draccus_project_init_main "$@"
  ;;
```

- [ ] **Step 5: Verify project init in a managed temp location**

Run:

```bash
tmp_home="$(mktemp -d)"
DRACCUS_HOME="$tmp_home" ./bin/draccus project init smoke-plan
test -f "$tmp_home/projects/smoke-plan/draccus.yaml"
test -f "$tmp_home/projects/smoke-plan/pyproject.toml"
test -f "$tmp_home/projects/smoke-plan/uv.lock"
test -x "$tmp_home/projects/smoke-plan/.venv/bin/pip"
"$tmp_home/projects/smoke-plan/.venv/bin/pip" 2>&1 | grep -qF "pip is disabled inside draccus"
rm -rf "$tmp_home"
./scripts/validate-static.sh
```

Expected: all checks pass.

- [ ] **Step 6: Commit**

```bash
git add lib/draccus-project.sh lib/draccus-cli.sh projects/_template
git commit -m "Add draccus project init"
```

---

### Task 6: Implement `shell`, `uv`, `notebook`, `doctor`, And `bundle show`

**Files:**
- Create: `lib/draccus-shell.sh`
- Create: `lib/draccus-doctor.sh`
- Create: `lib/draccus-notebook.sh`
- Modify: `lib/draccus-uv.sh`
- Modify: `lib/draccus-cli.sh`
- Modify: `scripts/validate-static.sh`

- [ ] **Step 1: Add new libs to static validation**

Add to `SHELL_FILES`:

```bash
"$DRACCUS_BUNDLE/lib/draccus-shell.sh"
"$DRACCUS_BUNDLE/lib/draccus-doctor.sh"
"$DRACCUS_BUNDLE/lib/draccus-notebook.sh"
```

- [ ] **Step 2: Move current shell behavior into `lib/draccus-shell.sh`**

Create `lib/draccus-shell.sh` by moving the shell startup functions into:

```bash
# shellcheck shell=bash

# shellcheck source=draccus-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-env.sh"
# shellcheck source=draccus-runtime.sh
source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

draccus_shell_main() {
  local bundle_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle)
        bundle_override="${2:-}"
        [[ -n "$bundle_override" ]] || { echo "draccus shell: --bundle requires a path" >&2; return 2; }
        shift 2
        ;;
      *)
        echo "draccus shell is interactive-only; use draccus run inside a project for commands" >&2
        return 2
        ;;
    esac
  done
  if [[ -n "$bundle_override" ]]; then
    DRACCUS_BUNDLE="$bundle_override"
    export DRACCUS_BUNDLE
  fi
  draccus_shell_ensure_starship
  draccus_shell_write_zdotdir
  draccus_runtime_exec_run env ZDOTDIR=/opt/draccus/cache/draccus-shell/zsh \
    SHELL=/opt/draccus/view/base-sys/bin/zsh \
    zsh
}
```

Keep the existing `draccus_shell_ensure_starship` and `draccus_shell_write_zdotdir` function bodies intact.

- [ ] **Step 3: Update `lib/draccus-uv.sh` to use runtime library and project config**

Replace direct legacy launcher calls with `draccus_runtime_exec_run`.

At the start of `draccus_uv_main`, add:

```bash
draccus_project_assert_config
```

Before calling runtime, set workspace:

```bash
local project_root
project_root="$(draccus_project_root_from_config)"
DRACCUS_WORKSPACE="$project_root"
export DRACCUS_WORKSPACE
```

- [ ] **Step 4: Implement notebook helper**

Create `lib/draccus-notebook.sh`:

```bash
# shellcheck shell=bash

# shellcheck source=draccus-project.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-project.sh"
# shellcheck source=draccus-runtime.sh
source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

draccus_notebook_main() {
  local port="8888" host="127.0.0.1" project_root
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port) port="${2:-}"; shift 2 ;;
      --host) host="${2:-}"; shift 2 ;;
      *) echo "draccus notebook: unknown argument '$1'" >&2; return 2 ;;
    esac
  done
  draccus_project_assert_config
  project_root="$(draccus_project_root_from_config)"
  DRACCUS_WORKSPACE="$project_root" draccus_runtime_exec_run bash -lc "
    set -euo pipefail
    if ! python -c 'import jupyterlab' >/dev/null 2>&1; then
      echo 'JupyterLab is not installed. Run: draccus uv pip install jupyterlab' >&2
      exit 2
    fi
    exec python -m jupyterlab --ip='$host' --port='$port' --no-browser
  "
}
```

- [ ] **Step 5: Implement doctor helper**

Create `lib/draccus-doctor.sh` with text and JSON modes:

```bash
# shellcheck shell=bash

# shellcheck source=draccus-layout.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-layout.sh"
# shellcheck source=draccus-runtime.sh
source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

draccus_doctor_main() {
  local json=0 bundle rc=0
  if [[ "${1:-}" == "--json" ]]; then
    json=1
  fi
  bundle="${DRACCUS_BUNDLE:-$(draccus_default_bundle)}"
  if [[ ! -x "$bundle/rootfs/bin/sh" && ! -e "$bundle/rootfs/bin/sh" ]]; then
    if ((json)); then
      printf '{"ok":false,"error":"default bundle missing","bundle":"%s"}\n' "$bundle"
    else
      echo "draccus doctor: default bundle is missing: $bundle" >&2
      echo "Install one with: draccus bundle unpack <archive>" >&2
    fi
    return 1
  fi
  if ! ls /dev/nvidia* >/dev/null 2>&1; then
    if ((json)); then
      printf '{"ok":false,"error":"no GPU devices visible","bundle":"%s"}\n' "$bundle"
    else
      echo "draccus doctor: no /dev/nvidia* devices visible; B200 training requires GPUs" >&2
    fi
    return 1
  fi
  if ! draccus_runtime_exec_run bash -lc '
    set -euo pipefail
    test "$DRACCUS_PREFIX" = /opt/draccus
    test "$SPACK_ROOT" = /opt/draccus/spack
    test "$(command -v uv)" = /usr/local/bin/uv
    test "$(command -v pip)" = /opt/draccus/shims/pip
    python - <<PY
import torch, jax, jaxlib, numpy, scipy
for mod in [torch, jax, jaxlib, numpy, scipy]:
    path = getattr(mod, "__file__", "")
    assert "/opt/draccus/" in path, (mod.__name__, path)
print("foundation imports OK")
PY
  '; then
    rc=1
  fi
  if ((json)); then
    if [[ "$rc" -eq 0 ]]; then
      printf '{"ok":true,"bundle":"%s"}\n' "$bundle"
    else
      printf '{"ok":false,"error":"runtime checks failed","bundle":"%s"}\n' "$bundle"
    fi
  elif [[ "$rc" -eq 0 ]]; then
    echo "draccus doctor: OK"
  fi
  return "$rc"
}
```

- [ ] **Step 6: Add dispatch cases**

In `lib/draccus-cli.sh`, add cases:

```bash
shell)
  shift
  source "$DRACCUS_BUNDLE/lib/draccus-shell.sh"
  draccus_shell_main "$@"
  ;;
uv)
  shift
  source "$DRACCUS_BUNDLE/lib/draccus-uv.sh"
  draccus_uv_main "$@"
  ;;
notebook)
  shift
  source "$DRACCUS_BUNDLE/lib/draccus-notebook.sh"
  draccus_notebook_main "$@"
  ;;
doctor)
  shift
  source "$DRACCUS_BUNDLE/lib/draccus-doctor.sh"
  draccus_doctor_main "$@"
  ;;
bundle)
  shift
  case "${1:-}" in
    show)
      source "$DRACCUS_BUNDLE/lib/draccus-layout.sh"
      if [[ "${2:-}" == "--json" ]]; then
        printf '{"default_bundle":"%s"}\n' "$(draccus_default_bundle)"
      else
        echo "Default bundle: $(draccus_default_bundle)"
      fi
      ;;
    *) draccus_die "expected: draccus bundle show [--json]" ;;
  esac
  ;;
```

- [ ] **Step 7: Verify commands**

Run:

```bash
./bin/draccus help shell
./bin/draccus bundle show --json
./bin/draccus doctor --json || true
./scripts/validate-static.sh
```

Expected:

- Help and bundle show work.
- Doctor may fail if environment is not GPU-ready; failure must be clear and JSON-shaped with `--json`.
- Gate 0 passes.

- [ ] **Step 8: Commit**

```bash
git add lib/draccus-shell.sh lib/draccus-doctor.sh lib/draccus-notebook.sh lib/draccus-uv.sh lib/draccus-cli.sh scripts/validate-static.sh
git commit -m "Add daily draccus workflow commands"
```

---

### Task 7: Implement Recorded `draccus run`

**Files:**
- Create: `lib/draccus-run-record.sh`
- Modify: `lib/draccus-cli.sh`
- Modify: `scripts/validate-static.sh`

- [ ] **Step 1: Add run-record lib to static validation**

Add to `SHELL_FILES`:

```bash
"$DRACCUS_BUNDLE/lib/draccus-run-record.sh"
```

- [ ] **Step 2: Create run record library**

Create `lib/draccus-run-record.sh`:

```bash
# shellcheck shell=bash

# shellcheck source=draccus-layout.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/draccus-layout.sh"
# shellcheck source=draccus-project.sh
source "$DRACCUS_BUNDLE/lib/draccus-project.sh"
# shellcheck source=draccus-runtime.sh
source "$DRACCUS_BUNDLE/lib/draccus-runtime.sh"

draccus_run_main() {
  local name="" no_record=0 runs_dir="" project_root project_name project_hash project_id run_id run_dir start_ts end_ts rc
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --no-record) no_record=1; shift ;;
      --runs-dir) runs_dir="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) echo "draccus run: unknown option '$1'" >&2; return 2 ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || { echo "draccus run: command required" >&2; return 2; }
  draccus_project_assert_config
  project_root="$(draccus_project_root_from_config)"
  project_name="$(draccus_project_name_from_config)"
  project_hash="$(draccus_hash_path "$project_root")"
  project_id="$(draccus_slug "$project_name")-$project_hash"
  if [[ -z "$runs_dir" ]]; then
    if runs_dir_cfg="$(draccus_project_runs_dir_from_config 2>/dev/null)"; then
      runs_dir="$runs_dir_cfg"
    else
      runs_dir="$(draccus_runs_root)"
    fi
  fi
  if ((no_record)); then
    DRACCUS_WORKSPACE="$project_root" draccus_runtime_exec_run "$@"
    return $?
  fi

  start_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run_id="$(draccus_timestamp_utc)"
  if [[ -n "$name" ]]; then
    run_id="$run_id-$(draccus_slug "$name")"
  fi
  run_dir="$runs_dir/$project_id/$run_id"
  mkdir -p "$run_dir/logs"
  cat >"$run_dir/run.json" <<EOF
{"schema_version":1,"project_id":"$project_id","project_root":"$project_root","bundle":"$DRACCUS_BUNDLE","started_at":"$start_ts","command":$(printf '%s\n' "$*" | python -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}
EOF

  set +e
  DRACCUS_WORKSPACE="$project_root" draccus_runtime_exec_run "$@" \
    > >(tee "$run_dir/logs/stdout.log") \
    2> >(tee "$run_dir/logs/stderr.log" >&2)
  rc=$?
  set -e
  end_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat >"$run_dir/result.json" <<EOF
{"schema_version":1,"exit_code":$rc,"finished_at":"$end_ts"}
EOF
  echo "draccus run: record written to $run_dir" >&2
  return "$rc"
}
```

- [ ] **Step 3: Add dispatch**

In `lib/draccus-cli.sh`:

```bash
run)
  shift
  source "$DRACCUS_BUNDLE/lib/draccus-run-record.sh"
  draccus_run_main "$@"
  ;;
```

- [ ] **Step 4: Verify success and failure records**

Run from a temporary project created by `draccus project init`:

```bash
tmp_home="$(mktemp -d)"
DRACCUS_HOME="$tmp_home" ./bin/draccus project init run-smoke
cd "$tmp_home/projects/run-smoke"
DRACCUS_HOME="$tmp_home" /data02/home/philip.yang/draccus/bin/draccus run --name ok -- bash -lc 'echo out; echo err >&2'
test -f "$tmp_home/runs/run-smoke-"*/20*/run.json
test -f "$tmp_home/runs/run-smoke-"*/20*/result.json
set +e
DRACCUS_HOME="$tmp_home" /data02/home/philip.yang/draccus/bin/draccus run --name fail -- bash -lc 'exit 7'
rc="$?"
set -e
test "$rc" -eq 7
rm -rf "$tmp_home"
./scripts/validate-static.sh
```

Expected: success exits 0; failing run exits 7; both write records.

- [ ] **Step 5: Commit**

```bash
git add lib/draccus-run-record.sh lib/draccus-cli.sh scripts/validate-static.sh
git commit -m "Record draccus run executions"
```

---

### Task 8: Remove Legacy Public Entrypoints And Update Validation

**Files:**
- Remove: legacy public files listed in the file map
- Modify: `scripts/validate-static.sh`
- Modify: `scripts/validate-all.sh`
- Modify: `lib/draccus-*.sh` as needed to stop referencing old entrypoints

- [ ] **Step 1: Replace validation references**

In `scripts/validate-static.sh`:

- Remove legacy public-file entries from `SHELL_FILES` and `LAUNCHERS`.
- Keep only `"$DRACCUS_BUNDLE/bin/draccus"` as public launcher.
- Replace checks containing `draccus run`/`draccus shell`/`draccus uv` with checks against library files and `bin/draccus`, for example:

```bash
check "single public draccus command exists" "test -x \"$DRACCUS_BUNDLE/bin/draccus\""
check "runtime library mounts shims" "grep -qF '/opt/draccus/shims' \"$DRACCUS_BUNDLE/lib/draccus-runtime.sh\""
check "shell library configures starship" "grep -qF 'starship init zsh' \"$DRACCUS_BUNDLE/lib/draccus-shell.sh\""
check "uv library blocks foundation installs" "grep -qF 'refusing to install foundation package' \"$DRACCUS_BUNDLE/lib/draccus-uv.sh\""
check "no legacy public entrypoints" "_draccus_no_legacy_public_entrypoints"
```

In `scripts/validate-all.sh`, replace:

```bash
old probe/build/run/offline launcher invocations
```

with:

```bash
"$DRACCUS_BUNDLE/bin/draccus" doctor
"$DRACCUS_BUNDLE/bin/draccus" build -- bash -lc '...'
"$DRACCUS_BUNDLE/bin/draccus" run --no-record -- bash -lc '...'
```

Do not keep the offline gate unless the workstream explicitly adds an approved `draccus offline` surface. If Gate 13 cannot be represented without the removed public entrypoint, mark this as a blocker in the tracker and ask the user whether to add an `offline` subcommand or defer Gate 13 migration.

- [ ] **Step 2: Remove legacy files**

Remove the legacy public files for run, build, shell, uv, probe, project init,
debug shell, and offline behavior. Task 8 completed this with `git rm`; keep
them absent rather than adding compatibility shims.

- [ ] **Step 3: Search for legacy public command references**

Run:

```bash
./scripts/validate-static.sh
```

Expected: the stale-reference checks pass. References in old closed workstream
logs may remain only if they are historical artifacts and not active
instructions; do not rewrite large historical logs.

- [ ] **Step 4: Run validation**

Run:

```bash
./scripts/validate-static.sh
```

Expected: passes. If `validate-static.sh` still runs doctor and doctor requires GPUs, run on the B200 host; otherwise update Gate 0 to keep GPU-requiring checks out of static validation and document that doctor is a runtime check.

- [ ] **Step 5: Commit**

```bash
git add -u bin scripts lib README.md DESIGN.md docs projects .workstream
git commit -m "Remove legacy draccus entrypoints"
```

---

### Task 9: Rewrite User-Facing Docs Around `draccus`

**Files:**
- Modify: `README.md`
- Modify: `DESIGN.md`
- Modify: `docs/tech-blog-hello-draccus.md`
- Modify: `docs/training-substrate-roadmap.md`
- Modify: `.workstream/INDEX.md`

- [ ] **Step 1: Update README command table**

Replace old launcher table with:

```markdown
| Command | Purpose |
|---|---|
| `draccus shell` | Open the native interactive ML shell |
| `draccus run -- <cmd>` | Run and record a project command |
| `draccus uv ...` | Manage project Python dependencies safely |
| `draccus doctor` | Check bundle, namespace, GPU, and foundation health |
| `draccus notebook` | Launch project JupyterLab |
| `draccus build -- <cmd>` | Writable foundation maintenance |
| `draccus project init <name>` | Create/initialize a model project |
| `draccus bundle show` | Show selected/default bundle |
```

- [ ] **Step 2: Update DESIGN launcher sections**

Change the launcher model to say:

```markdown
`bin/draccus` is the only public entrypoint. Runtime and build namespace mechanics live in `lib/draccus-runtime.sh`; shell startup lives in `lib/draccus-shell.sh`; project and uv policy live in `lib/draccus-project.sh` and `lib/draccus-uv.sh`.
```

Keep the existing details about read-only runtime, writable build mode, cache locations, and zsh/starship behavior, but express commands through `draccus <subcommand>`.

- [ ] **Step 3: Update tech blog examples**

Replace command examples:

```bash
./bin/draccus shell
./bin/draccus run -- bash -lc 'python -V'
./bin/draccus uv pip install transformers
```

with:

```bash
draccus shell
draccus run -- python -V
draccus uv pip install transformers
```

- [ ] **Step 4: Verify no stale future-facing legacy commands**

Run:

```bash
./scripts/validate-static.sh
```

Expected: no active docs/scripts references. If historical closed workstream docs still mention old commands, leave them only if they are clearly historical and not user guidance.

- [ ] **Step 5: Run Gate 0 and commit**

```bash
./scripts/validate-static.sh
git add README.md DESIGN.md docs projects .workstream/INDEX.md
git commit -m "Document single draccus command surface"
```

---

### Task 10: Final Acceptance And Workstream Closeout

**Files:**
- Modify: `.workstream/single-command-cli/tracker.org`
- Modify: `.workstream/INDEX.md`

- [ ] **Step 1: Run command smoke tests**

Run:

```bash
./bin/draccus --help
./bin/draccus help shell
./bin/draccus help run
./bin/draccus bundle show
./bin/draccus doctor
```

Expected:

- Help commands exit 0.
- `bundle show` exits 0.
- `doctor` exits 0 on a configured B200 host. If it fails, the failure message must be actionable and the workstream cannot close.

- [ ] **Step 2: Run project/run smoke**

Run:

```bash
tmp_home="$(mktemp -d)"
DRACCUS_HOME="$tmp_home" ./bin/draccus project init final-smoke
cd "$tmp_home/projects/final-smoke"
DRACCUS_HOME="$tmp_home" /data02/home/philip.yang/draccus/bin/draccus run --name smoke -- python -c 'print("ok")'
test -f "$tmp_home/runs/final-smoke-"*/20*/run.json
test -f "$tmp_home/runs/final-smoke-"*/20*/logs/stdout.log
cd /data02/home/philip.yang/draccus
rm -rf "$tmp_home"
```

Expected: run record exists and stdout log contains `ok`.

- [ ] **Step 3: Run Gate 0**

```bash
./scripts/validate-static.sh 2>&1 | tee .workstream/single-command-cli/artifacts/final-validate-static.log
```

Expected: `RESULT: SUCCESS`.

- [ ] **Step 4: Update tracker and index**

Mark all completed tasks `DONE`, fill retrospective with concrete observations from this implementation. Use this exact shape, replacing the example text with the actual observed facts before committing:

```org
* Retrospective
- Surprises: The implementation exposed one concrete issue that was not obvious from the design.
- Automate next time: One repeated validation or migration step should become a script/check.
- Doc gaps: One doc section needed extra detail during implementation.
```

Update `.workstream/INDEX.md` status for `single-command-cli` to closed with the completion date and outcome.

- [ ] **Step 5: Final commit**

```bash
git add .workstream/single-command-cli/tracker.org .workstream/single-command-cli/artifacts/final-validate-static.log .workstream/INDEX.md
git commit -m "Close single-command CLI workstream"
```

Expected: working tree clean after commit.

---

## Self-Review Notes

Spec coverage:

- Single public `bin/draccus`: Tasks 2, 8, 9.
- Bash-first thin dispatcher and library boundaries: Tasks 2, 3, 4, 6, 7.
- `draccus run` recorded by default with live tee and child exit code: Task 7.
- `draccus shell` native, interactive-only, works outside projects: Task 6.
- Project-bound `uv` and `notebook`: Tasks 5 and 6.
- `doctor` merged with probe and GPU required by default: Task 6.
- `project init` creates `draccus.yaml`, generic `pyproject.toml`, `.venv`, `uv.lock`, and pip shims: Task 5.
- Remove legacy entrypoints and docs: Tasks 8 and 9.
- Gate 0 and workstream closeout: Tasks 8, 9, 10.

Known risk to resolve during execution:

- Gate 13 currently uses offline behavior. The approved first command surface excludes `offline`; Task 8 explicitly treats this as a possible blocker requiring a user decision rather than silently reintroducing an offline command.
