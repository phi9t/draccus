# Draccus Training Substrate Program

## 0. Thesis

Draccus should evolve from an environment substrate into an experiment substrate without losing the native shell ergonomics that make it useful for research work. The program order is explicit:

1. **User workflow first.** One command, strong help, native shell, project setup, recorded runs, doctor, notebook.
2. **Bundle distribution second.** Package and install the already-built shared foundation bundle cleanly under `~/.automata/draccus`.
3. **Experiment correctness third.** Add provenance, replay, resume checks, data/artifact locking, and failure classification after the UX and bundle model are stable.

The first implementation milestone is intentionally breaking: `draccus` becomes the only public command. Future-facing docs should describe only `draccus <subcommand>`.

## 1. Product Contract

Draccus has three nested contracts:

```text
Environment contract:
  /opt/draccus, pinned rootfs, Spack base-ml, uv project overlay, GPU driver pass-through

Project contract:
  draccus.yaml, pyproject.toml, .venv, uv.lock, selected bundle, project-scoped commands

Run contract:
  recorded command execution, logs, result metadata, later provenance/replay/resume semantics
```

The current repository already enforces much of the environment contract. This program makes the project and run contracts first-class without expanding Draccus into a cluster orchestrator.

## 2. User Experience North Star

The default experience should be:

```bash
draccus shell
draccus project init llama-debug
draccus uv pip install transformers datasets accelerate
draccus run --name smoke -- python train.py
```

Quality bars:

- `draccus shell` feels like entering a native host, not a wrapper ceremony.
- `draccus run` records by default and still behaves like the command it runs: live output and the child exit code.
- Project setup is opinionated and complete: `draccus.yaml`, generic `pyproject.toml`, `.venv`, `uv.lock`, and pip shims.
- Failure messages include the next command to run.
- Help output is a real product surface, not an afterthought.

## 3. Shared State Layout

Generated and distributed Draccus state lives outside model repositories:

```text
~/.automata/draccus/
  bundles/
    default/
  runs/
    <project-name>-<path-hash>/
      <run-id>/
  projects/
    <managed-project-name>/
```

Model repositories own their own `draccus.yaml`. A project can override the default shared bundle with a `bundle:` path. If no bundle is specified, runtime commands use `~/.automata/draccus/bundles/default`.

If the default bundle is missing, commands fail with bootstrap/distribution guidance. They do not automatically create or download a foundation.

## 4. First Command Surface

The first milestone public surface is:

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

### `draccus shell`

Works anywhere. It uses the default bundle unless `--bundle` is supplied. It is interactive-only, unrecorded, and should preserve the current controlled zsh experience: foundation Python active, project `.venv` active when present, compact prompt, and clear writable surfaces.

### `draccus run`

Requires a project with `draccus.yaml`. It records by default, supports `--name`, `--no-record`, and `--runs-dir`, streams stdout/stderr live while teeing logs, and exits with the child command's exit code.

The first record is operational:

```text
run.json          command, cwd, project id, bundle path, timestamps
result.json       exit code and duration
logs/stdout.log
logs/stderr.log
```

Provenance fields land in the later `runtime-provenance` workstream.

### `draccus uv`

Requires a project. It remains the supported way to mutate project Python dependencies while preserving the foundation package boundary.

### `draccus doctor`

The user-facing health command. It checks default bundle presence, bwrap entry, canonical paths, uv/pip shim behavior, GPU presence, and torch/jax/numpy/scipy provenance. GPU absence fails by default. `--json` supports future tooling.

### `draccus notebook`

Requires a project. It assumes Jupyter is a project dependency. If Jupyter is missing, it prints exact `draccus uv pip install jupyterlab` guidance rather than mutating the project unexpectedly.

### `draccus build`

First-class but clearly marked as the writable foundation-maintenance path. Normal research work should use shell/run/uv.

### `draccus project init`

Inside a git repository, initializes the git root. Otherwise, creates a managed project under `~/.automata/draccus/projects/<name>/`. It creates or updates:

- `draccus.yaml`
- generic `pyproject.toml`
- `.venv` using the foundation Python with `--system-site-packages`
- `uv.lock`
- neutralized `.venv/bin/pip*` shims

### `draccus bundle show`

Reserved in the first milestone so the later packaging workstream can add `pack` and `unpack` under the same namespace.

## 5. Workstreams

### 5.1 `single-command-cli`

Path: `.workstream/single-command-cli/`

Goal: land the breaking CLI consolidation and recorded operational run behavior.

Scope:

- Add `bin/draccus` as a Bash-first thin dispatcher.
- Move reusable behavior into `lib/` so a future Rust CLI can replace the router.
- Remove legacy per-command entrypoints rather than shimming them.
- Implement shell/run/uv/doctor/notebook/build/project-init/bundle-show.
- Update Gate 0 and pre-commit expectations to enforce the single public surface.
- Rewrite README and DESIGN around the new CLI.

Acceptance:

- `draccus --help` and subcommand help are polished.
- `draccus shell` is native, interactive-only, and works outside projects.
- `draccus run` records operational metadata by default and preserves child exit codes.
- Project commands require `draccus.yaml`.
- Gate 0 passes.

### 5.2 `bundle-packaging`

Path: `.workstream/bundle-packaging/`

Goal: make local distribution of the existing built bundle practical.

Command surface:

```text
draccus bundle pack <archive>
draccus bundle unpack <archive> [--force]
draccus bundle show [--json]
```

`bundle pack` packages the current bundle only. The archive includes runnable source/runtime state and excludes caches, build products, runs, projects, workstreams, and transient artifacts. `bundle unpack` installs to `~/.automata/draccus/bundles/default` by default and refuses overwrite unless `--force`.

Acceptance:

- Pack/unpack/show work locally.
- Unpacked bundle can pass doctor.
- Manifest schema is versioned and remote-channel-ready.

### 5.3 `runtime-provenance`

Path: `.workstream/runtime-provenance/`

Goal: extend operational run records into reproducibility records.

Add:

- project config snapshot
- bundle identity
- git commit and bounded dirty status
- selected environment variables with redaction
- foundation import provenance
- schema-versioned JSON metadata

Acceptance:

- Run metadata is useful for debugging and replay planning.
- Secret/redaction and size boundaries are documented.
- Recording remains cheap enough for daily use.

### 5.4 `release-channels`

Path: `.workstream/release-channels/`

Goal: turn packaged B200 bundles into inspectable releases with validation evidence.

Add:

- foundation release manifests
- validation reports
- compatibility contracts: target GPU, driver floor, known caveats
- reveal/check workflow for research engineers
- future named channel design notes

Acceptance:

- A packaged foundation can be inspected independently.
- Release reports distinguish passed, skipped, and unavailable gates.
- B200 validation evidence is explicit.

### 5.5 `experiment-correctness`

Path: `.workstream/experiment-correctness/`

Goal: add higher-level experiment correctness after recorded provenance exists.

Add:

- replay contract reconstruction
- checkpoint metadata sidecars
- resume compatibility checks with explicit override semantics
- data/artifact locking modes
- coarse failure classification

Acceptance:

- Replay explains whether a run contract can be reconstructed.
- Resume validates declared compatibility instead of guessing.
- Data/cache modes make floating vs snapshot behavior explicit.

## 6. Dependency Graph

```text
single-command-cli
  |-- bundle-packaging
  |     `-- release-channels
  `-- runtime-provenance
        `-- experiment-correctness
```

Existing workstreams remain valid. The CLI consolidation must coordinate with any open workstream or docs that still refer to the old command surface.

## 7. Orchestration Boundary

Draccus owns deterministic local runtime correctness:

- selected bundle identity
- canonical namespace paths
- project overlay behavior
- local GPU visibility and foundation import provenance
- run record emission

External orchestrators own cluster-level concerns:

- node placement
- rendezvous
- membership
- retries
- global coordination

The integration surface is typed local artifacts and JSON, not scheduler logic inside Draccus.

## 8. Validation Program

The implementation workstreams must keep validation aligned with the product surface:

- Gate 0 enforces the single public command after `single-command-cli`.
- Doctor is the daily human health command and fails on missing GPU by default.
- Full foundation validation remains the acceptance path for bundle/release work.
- Recorded run tests cover success and failure, including preserved child exit code.
- Later provenance/replay work adds schema and sample artifact checks.

## 9. Roadmap Summary

1. Land `single-command-cli`.
2. Land local `bundle-packaging`.
3. Expand run records through `runtime-provenance`.
4. Promote packaged foundations through `release-channels`.
5. Add replay/resume/locking through `experiment-correctness`.

The durable direction is simple: one command, shared bundles, project-local overlays, recorded runs, and progressively stronger experiment guarantees.
