# Draccus Training Substrate Roadmap

## 0) Core thesis

**Usability north star:** running an experiment should feel as simple as opening a shell and typing one command (`draccus run ...`) — and it should work every time under the documented contract. The shell workflow itself should be the best-in-class default for exploring, iterating, launching notebooks, and quick model tinkering.

- **Draccus should evolve from an environment substrate into an experiment substrate without losing ergonomics.** The current platform strongly enforces the filesystem/runtime foundation (`/opt/draccus`, pinned rootfs, Spack-owned base-ml, uv-owned project overlays, read-only runtime foundation, validation gates), but training reliability also needs first-class contracts for launch, provenance, data snapshots, checkpoints, metrics, failure modes, and replayability — delivered through a simple default UX.
- **Primary bottlenecks are experiment invalidation, not just raw performance:** reproducibility/debug latency, single-node multi-GPU launch fragility, dependency drift, artifact ambiguity, missing recovery, and weak autonomous-agent safety.
- **P0 missing abstraction #1: run manifest.** Each run should emit immutable run records (`run.json` + `run.lock`) that capture foundation digest, overlay lock state, commit + dirty diff, command/config/seeds, data/model IDs, topology/driver/NCCL facts, and validation status.
- **P0 missing abstraction #2: single-node runtime/preflight contract.** Beyond local gates, Draccus should expose a stable local-runtime contract to external orchestrators (for example Ray, Monarch, Slurm wrappers, or `torchrun` launchers): local rank env expectations, GPU/NIC checks, NCCL smoke-test outputs across local GPUs, and topology artifacts.
- **Agents need typed operations and policy controls, not only shell-shaped interfaces.** Introduce machine-readable operations centered on local execution/provenance (`create_experiment`, `run_local`, `status`, `tail_logs`, `compare_runs`, `resume`, `collect_artifacts`) plus policy envelopes controlling writable paths and network mode. Multi-node orchestration remains outside Draccus.
- **Highest leverage is pragmatic infrastructure:** run manifests, structured run directories/logs, checkpoint+resume protocol, single-node multi-GPU validation, artifact/data locking, pre-built foundation channels for B200, and agent-safe profiles.
- **Fast falsifiers:** replay failure from run manifest, NCCL preflight mismatch vs native launch, base package shadowing through overlay, silent agent mutation of shared datasets/checkpoints, or inability to classify failures as env/code/data/hardware within one pass.
- **Priority:** P0 run provenance + single-node preflight + checkpoint/artifact contracts + one-command UX path; P1 observability + agent API/policy + foundation channels; P2 dashboard/UX convenience.

## 1) Three nested contracts

```text
Environment contract:
  /opt/draccus, rootfs, Spack base-ml, uv overlay, GPU driver pass-through

Experiment contract:
  run manifest, inputs, outputs, metrics, checkpoints, seeds, data/model versions

Execution contract:
  single-node runtime contract, local ranks, preflight, monitoring, failure classification, resume
```

Draccus already enforces most of the environment contract. The roadmap extends that to make experiments immutable, inspectable, replayable objects.

### Suggested vocabulary

- **Foundation digest:** hash over rootfs metadata, Spack concrete spec, view contents, uv override list, launcher scripts, and pinned versions.
- **Experiment spec:** declarative run intent (command, config, data/model refs, resources, backend, env, logging, checkpoint policy).
- **Run record:** immutable launch-time record (resolved spec + dynamic node/GPU/driver/topology facts).
- **Preflight:** low-cost guard checks before expensive allocation/first step.
- **Replay:** rerun from run record.
- **Resume:** restart from checkpoint under same or explicitly-declared changed contract.
- **Agent policy profile:** bounded permissions for autonomous operators.


## 1.5) Simplicity and reliability principles

1. **One obvious happy path:** `draccus run <cmd>` should be the default that most users need most of the time.
2. **Safe defaults, optional depth:** advanced knobs (preflight modes, policy details, sink configuration) must remain optional and discoverable.
3. **Predictable every-run behavior:** the same inputs under the same contract should produce the same launch behavior and artifacts every time.
4. **No orchestrator burden on researchers:** Draccus exposes local context; users should not need to reason about scheduler internals to run locally.
5. **Actionable failure messages:** if a run fails, the first error should clearly say what to do next, not require spelunking through opaque logs.

## 1.6) Shell-first product experience

Draccus should be the default place where researchers and agents go to quickly understand the environment and iterate safely.

Primary shell workflows to optimize:

1. **Inspect the environment quickly**
   - `draccus-shell` opens fast with clear banners: foundation version/channel, Python version, GPU visibility, active project overlay, and where writes persist.
2. **Run small experiments immediately**
   - `draccus run <cmd>` works with minimal ceremony and leaves a searchable run record by default.
3. **Launch notebooks smoothly**
   - `draccus-shell` + one obvious notebook command path (e.g., Jupyter/Lab helper) with documented ports, working directory, and persistence semantics.
4. **Iterate on dependencies safely**
   - package iteration stays simple (`draccus-uv ...`) while preserving non-shadowing guarantees for foundation packages.
5. **Tinker without fear**
   - local edits, temporary experiments, and restarts should be cheap; destructive operations should require explicit intent.

Shell UX quality bars:

- **Time-to-first-command** in shell should be short and stable.
- **Time-to-first-training-step** for template experiments should be predictable.
- **Error messages** should explain what failed, why, and the next command to run.
- **State model clarity:** users should always know which paths are persistent vs ephemeral.

## 2) Mechanism

### 2.1 First-class run directory

```text
/workspace/<project>/
  draccus.yaml
  configs/
  src/
  runs/
    <timestamp>_<slug>/
      run.json
      run.lock
      env/
        spack-concrete.txt
        uv.lock
        import-provenance.json
        nvidia-smi-q.txt
        nccl-env.json
        topology.json
      logs/
        stdout.log
        stderr.log
        events.jsonl
        metrics.jsonl
        launcher.log
      checkpoints/
      artifacts/
      agent/
        actions.jsonl
        approvals.jsonl
        tool-results.jsonl
```

### 2.2 CLI surface (simple by default)

```bash
draccus experiment init --template torch-ddp
draccus experiment validate
draccus run --name llama-debug --config configs/7b.yaml -- torchrun train.py
draccus run status <run_id>
draccus run tail <run_id>
draccus run replay <run_id>
draccus run resume <run_id> --checkpoint latest
draccus run diff <run_a> <run_b>
```

Layer this above `draccus-run` so existing namespace/path contracts remain intact. The UX target is: enter shell, run one command, get deterministic behavior and a complete run record.

### 2.3 Explicit launch topology and preflight

Add a runtime block (local GPU count, local-rank mapping expectations, network, policy checks), then enforce:

1. Resolve run spec.
2. Run probe on the local host and emit machine-readable context for the orchestrator.
3. Verify bundle/foundation/overlay identity and import provenance.
4. Verify driver/GPU/topology + IB/NIC constraints.
5. Run tiny local-GPU all-reduce smoke (single node).
6. Persist all preflight artifacts in run env.

### 2.4 Artifact/data locking

- Datasets default read-only.
- Outputs only to run dir + declared artifact store.
- HF/model caches either snapshot-locked or explicitly floating.
- If run claims offline reproducibility, require offline validation path.

### 2.5 Checkpoint/resume contract

Standardize checkpoint metadata (step, hashes, RNG/optimizer/dataloader state, config hash), atomic write semantics, and resume compatibility checks against original run manifest with explicit override mechanism.

### 2.6 Structured observability

Emit `events.jsonl` with lifecycle, preflight, step, checkpoint, and classified-failure events; capture low-overhead telemetry with configurable sampling.

### 2.7 Agent-safe profiles

Policy-driven bwrap/write scope/network/scale limits; require approvals for scaling/network/foundation mutation; log agent actions as structured records.

### 2.8 Foundation release channels

Define immutable channels with explicit manifests, locks, buildcache URIs, validation reports, driver floors, supported architectures, and deprecation policy.


### 2.8.1 Pre-built foundation distribution strategy (B200 first)

Most users should **not** build the foundation stack themselves. Building Torch/JAX/CUDA/cuDNN/NCCL from source is expensive and should happen in a small number of controlled build pipelines.

Baseline strategy:

- **Primary target (now):** B200 / `cuda_arch=100` pre-built foundations.
- **Future targets (later):** H100, H200, A100 channels as separate immutable variants.
- **Build once, ship many:** foundation bundles are built a few times, then distributed across many nodes via image/buildcache artifacts.
- **Immutable identity:** every shipped foundation has a digest, manifest, validation report, and compatibility contract (driver floor, GPU class, known caveats).

Researcher workflow expectation:

- Pull/select a validated foundation channel, then start working immediately in `draccus-shell` / `draccus run`.
- No local foundation rebuild required for normal experimentation.
- If a channel is selected, Draccus surfaces exactly what was selected and how it was validated.

### 2.9 Shell ergonomics primitives

- Provide a `draccus-shell` startup summary that shows foundation digest/channel, overlay status, CUDA visibility, and writable surfaces.
- Provide first-class helpers for common interactive flows (`draccus notebook`, `draccus status`, `draccus doctor`) with machine-readable `--json` where applicable.
- Keep dependency iteration one-command simple (`draccus-uv pip install ...`) while continuously enforcing layering constraints.
- Ensure every helper command has crisp, copy-pastable remediation guidance when checks fail.

## 3) Performance model

### Startup decomposition

\[
T_start = T_manifest + T_snapshot + T_preflight + T_launcher + T_framework_init + T_first_batch
\]

Targets: low-ms manifest assembly, seconds-scale env snapshot, bounded preflight (single-node seconds, including local multi-GPU smoke), and minimal launch overhead relative to run duration.

### Step decomposition

\[
T_step = T_data + T_h2d + T_fwd + T_bwd + T_comm + T_opt + T_logging + T_checkpoint_amortized
\]

Draccus overhead should primarily affect logging/checkpoint paths and reduce `T_comm` failures by better preflight, without meaningful hot-loop slowdown.

## 4) Implementation increments

1. **Run recorder (`draccus-run-recorded`)**
   - Create run dir; write manifest/lock; snapshot commit/env/import facts; tee logs; record exit/failure classification.
2. **Preflight commands (`draccus experiment validate`)**
   - Single-node scopes with import/layering/driver/GPU/NCCL checks.
3. **Orchestrator handoff interface (`draccus context --json`, `draccus preflight --json`)**
   - Emit local contract + verification artifacts that external orchestrators consume; keep Draccus orchestration-agnostic.
4. **Agent JSON API (`draccus agent ... --json`)**
   - Typed create/run_local/status/tail/compare endpoints.

## 5) Validation program

Add a product-level KPI here: **first-try success rate** for `draccus run` on supported hosts should trend toward ~100% for standard templates and documented workflows.


### 5.1 Foundation release validation and reveal protocol

For each pre-built foundation release (especially B200), require:

1. **Build-time verification**
   - Concrete Spack lock + manifest captured and signed/hashed.
   - Reproducible build metadata: toolchain, source revisions, patch set, build timestamps.
2. **Post-build technical validation**
   - Gate sequence relevant to foundation integrity (static checks, base-sys/base-ml checks, layering checks, offline checks where applicable).
   - Single-node multi-GPU runtime smoke on representative B200 hardware.
3. **Research-engineer reveal checklist**
   - A human-readable release note plus machine-readable report showing imports, CUDA/NCCL health, topology/probe outputs, and known limitations.
   - A one-command "reveal" path so research engineers can independently confirm the release works (`draccus doctor --foundation <channel>` style UX target).
4. **Promotion policy**
   - Channel moves to `stable` only after all mandatory checks pass and reveal review is signed off.

1. Run-manifest replay test.
2. Single-node multi-GPU preflight + orchestrator-handoff equivalence test.
3. Agent policy red-team.
4. Overlay shadowing stress test.
5. Checkpoint/resume integrity test.
6. Observability overhead sweep.
7. Offline data/model reproducibility test.
8. Foundation channel compatibility matrix.
9. Rule-based failure-classification benchmark.
10. Shell UX benchmark: startup latency, notebook launch success, package-iteration flow success, and first-try run success.

## 6) Immediate missing pieces (shortlist)

- Manifest schema + emitter.
- Orchestrator handoff commands (`draccus context --json`, `draccus preflight --json`).
- Single-node multi-GPU NCCL/IB validation gate with machine-readable output for orchestrators.
- Standard provenance capture bundle.
- Artifact/data locking policy.
- Checkpoint metadata + resume compatibility enforcement.
- Agent-safe runtime policy + typed API.
- Foundation channel governance.
- Pre-built B200 foundation packaging/distribution pipeline (build once, ship many) with signed manifests and reproducible validation reports.
- Failure classifier.
- Overhead benchmarks.
- Shell UX guardrails: shell startup summary, notebook helper, `draccus doctor`, and latency/error-message regression checks.

## 7) Orchestration boundary (explicit)

Draccus is intentionally **blissfully unaware** of cluster-level communication/orchestration complexity.

- External orchestrators (Ray, Monarch, Slurm wrappers, Kubernetes controllers, etc.) own node placement, rendezvous, retries, membership, and global coordination.
- Draccus owns the local runtime contract: foundation identity, import provenance, local GPU/NIC topology facts, preflight checks, and run-record emission.
- Integration surface is typed artifacts/JSON, not scheduler logic inside Draccus.

This keeps Draccus focused on deterministic local correctness while still enabling rich orchestration through explicit handoff context.

---

**Bottom line:** Draccus already makes the ML foundation path-stable and mostly immutable. The next step is to apply the same rigor to experiment state itself so runs are replayable, diagnosable, and safe for both humans and agents — while preserving a dead-simple workflow where users can open a shell, type `draccus run ...`, and trust it to work consistently.


## 8) Translation to current codebase (concrete next PRs)

To make this roadmap real, implementation should map directly to existing Draccus entrypoints and gate scripts instead of introducing parallel abstractions too early.

### 8.1 PR-1: Shell session quality (zero-friction default)

Use existing commands as the base:

- `bin/draccus-shell` (interactive entrypoint)
- `bin/draccus-run` (non-interactive command entrypoint)
- `bin/draccus-uv` (safe package iteration path)

Immediate improvements:

1. Add a concise shell banner (opt-out via env var) printed by `draccus-shell` that shows:
   - foundation channel/digest (or “unknown” if not yet modeled),
   - Python version,
   - CUDA/GPU visibility summary,
   - active workspace path,
   - writable vs read-only surfaces.
2. Add a `bin/draccus-doctor` command that runs a fast subset of checks:
   - namespace/path sanity (`bin/draccus-probe`),
   - foundation import sanity (lightweight import checks),
   - uv layering sanity (quick check against known protections).
3. Add a `bin/draccus-notebook` helper for standard local Jupyter launch with clear defaults.

Acceptance:

- `draccus-shell` remains fast and predictable.
- A researcher can run shell → doctor → notebook without reading internal scripts.
- Error output includes a next-command hint.

### 8.2 PR-2: Run record wrapper around existing launcher

Do **not** replace `draccus-run`. Add a wrapper that composes it.

- New command shape: `bin/draccus-run-recorded`.
- Reuse current runtime contract from `bin/draccus-run`.

Minimum record output in `runs/<id>/`:

- `run.json` (command, cwd/workspace, timestamp, seed/config pointers if supplied)
- `env/probe.json` (from `draccus-probe` output transformed to JSON)
- `env/imports.json` (torch/jax/numpy import provenance paths)
- `logs/stdout.log`, `logs/stderr.log`
- `result.json` (exit code, duration, coarse failure class)

Acceptance:

- `draccus-run-recorded -- python -c 'import torch'` always emits a complete run folder even on failure.
- Existing `draccus-run` behavior remains unchanged.

### 8.3 PR-3: Foundation release artifact + reveal command (B200-first)

Build on existing validation gates and pre-built bundle posture.

- Keep source builds concentrated in controlled pipelines (`draccus-build` path).
- Publish immutable pre-built B200 foundation artifacts with manifest metadata.
- Add `draccus foundation show` (or similar) to print selected foundation identity and validation status.

Release evidence should include:

- lock/spec snapshot,
- gate outputs (`validate-static`, `draccus-probe`, `validate-base-sys`, `validate-base-ml`, `validate_uv_layering`, offline check as applicable),
- compatibility contract (GPU target + driver floor),
- known caveats.

Acceptance:

- Research engineers can independently “reveal” a release from shipped metadata and a one-command local verification path.
- Most users never need to run foundation source builds.

### 8.4 PR-4: Gate wiring for UX + release integrity

Keep Gate 0 as fast local enforcement and add narrowly scoped checks:

1. Shell UX static checks:
   - shell helper scripts are executable,
   - help output includes key commands,
   - user-facing error sentinel strings are present.
2. Release metadata consistency checks:
   - if a foundation channel manifest exists, required fields are present.
3. Optional full validation extension:
   - keep `scripts/validate-all.sh` as source of truth for expensive checks.

Acceptance:

- Developers get quick failures for broken UX paths.
- Release metadata drift is caught before publishing.

### 8.5 Measurement plan tied to real commands

Track these metrics from actual command flows:

- **Shell time-to-first-command:** `time ./bin/draccus-shell -lc 'true'`
- **Run first-try success:** fraction of successful `draccus-run-recorded` invocations for standard templates.
- **Doctor usefulness:** fraction of common setup failures that `draccus-doctor` classifies with actionable hints.
- **Notebook success:** success rate + time-to-ready for `draccus-notebook`.

These metrics should be collected from scripted smoke runs, not ad-hoc anecdotes.
