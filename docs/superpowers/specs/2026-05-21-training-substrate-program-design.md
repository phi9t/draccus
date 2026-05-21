# Training Substrate Program Design

Date: 2026-05-21
Status: Approved for workstream planning

## Goal

Turn `docs/training-substrate-roadmap.md` from a broad vision into an executable Draccus program. The program prioritizes user workflow first, then bundle distribution, then deeper experiment correctness.

## Ordering Principles

1. User workflow first: Draccus should feel like one coherent tool, with a native shell experience and clear help.
2. Release and distribution second: the already-built foundation bundle should be easy to package, move, install, and inspect.
3. Experiment correctness third: provenance, replay, checkpoint compatibility, data locking, and failure classification build on the stable UX and bundle model.

## Workstream Decomposition

### `single-command-cli`

This is the first implementation workstream. It is a breaking consolidation around one public command: `bin/draccus`.

The first command surface is:

```text
draccus shell
draccus run [--name NAME] [--no-record] [--runs-dir DIR] -- <cmd>
draccus uv ...
draccus doctor [--json]
draccus notebook [--port PORT] [--host HOST]
draccus build -- <cmd>
draccus project init <name> [--path PATH]
draccus bundle show
draccus help
```

`draccus shell` is the lowest-friction entrypoint. It works anywhere, uses the default bundle unless `--bundle` is supplied, is interactive-only, stays unrecorded, and preserves the current native zsh/base-ml/project-venv experience.

`draccus run` requires a project with `draccus.yaml`, records by default, streams and tees stdout/stderr, writes run artifacts under `~/.automata/draccus/runs/<project-name>-<hash>/<run-id>/`, and exits with the child command's exit code. The first record is operational only: command, cwd, project id, bundle path, timestamps, exit code, and stdout/stderr logs.

`draccus uv` and `draccus notebook` require a project. `draccus uv` is the supported project dependency path. `draccus notebook` assumes Jupyter is a project dependency and prints the exact install guidance when it is missing.

`draccus doctor` absorbs the former contract-probe role and becomes the user-facing health command. It checks default bundle presence, bwrap entry, canonical paths, uv/pip shim behavior, GPU presence, and torch/jax/numpy/scipy provenance. GPU absence fails by default.

`draccus project init` initializes a git root when run in a repo; otherwise it creates a managed project under `~/.automata/draccus/projects/<name>/`. It writes `draccus.yaml`, creates or updates generic `pyproject.toml`, creates `.venv` using the foundation Python with `--system-site-packages`, writes `uv.lock`, and neutralizes `.venv/bin/pip*`.

The legacy per-command entrypoints are removed rather than shimmed. Documentation describes only `draccus <subcommand>`.

### `bundle-packaging`

Implement local distribution for the already-built bundle:

```text
draccus bundle pack <archive>
draccus bundle unpack <archive> [--force]
draccus bundle show [--json]
```

The default shared layout is:

```text
~/.automata/draccus/
  bundles/default/
  runs/
  projects/
```

`bundle unpack` installs to `~/.automata/draccus/bundles/default` by default and refuses to overwrite unless `--force`. `bundle pack` packages the current bundle only. Archives include runnable source/runtime state and exclude caches, build products, runs, projects, workstream artifacts, and transient files. The manifest format should leave room for future remote channels.

### `runtime-provenance`

Extend operational run records into reproducibility records: git commit and dirty status, selected environment variables, import provenance for foundation packages, `draccus.yaml` snapshot, bundle identity, and machine-readable JSON summaries.

### `release-channels`

Define B200-first release evidence and reveal flows: foundation manifests, validation reports, compatibility contracts, bundle identity, local reveal checks, and eventual named channels or remote registries.

### `experiment-correctness`

Add higher-level experiment guarantees after the CLI and provenance substrate exist: replay, resume metadata sidecars, checkpoint compatibility, data/artifact locking, failure classification, and eventually agent policy controls.

## Dependency Graph

```text
single-command-cli
  |-- bundle-packaging
  |     `-- release-channels
  `-- runtime-provenance
        `-- experiment-correctness
```

`single-command-cli` owns the breaking public surface and must land first. `bundle-packaging` depends on that surface and defines portable bundle archives. `runtime-provenance` depends on recorded run directories. Release channels build on bundle packaging. Experiment correctness builds on recorded provenance.

## Documentation Requirements

The roadmap becomes the program overview. The first workstream also rewrites README and DESIGN around the single command, updates command help, and removes legacy command names from future-facing docs.

## Validation Requirements

Planning-only edits do not require Gate 0 unless `bin/`, `lib/`, `scripts/`, `envs/`, or `mise.toml` change. The `single-command-cli` implementation must update Gate 0 and pre-commit in the same workstream so the single command surface is enforced immediately.

## Risks

| Risk | Mitigation |
|---|---|
| Breaking CLI removal disrupts existing scripts | Treat the workstream as intentionally breaking; update all repo docs and validation at once. |
| Bash router grows too large | Keep `bin/draccus` thin and move reusable logic to `lib/`, preserving a future Rust CLI path. |
| Run recording becomes too ambitious | First milestone records operational facts only; provenance moves to `runtime-provenance`. |
| Bundle registry complexity arrives too early | First packaging milestone supports explicit paths and local archives only. |
