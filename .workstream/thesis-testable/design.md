# Workstream: testable thesis — host contract + base-image matrix

**Owner:** unassigned
**Status:** Blocked on: user sign-off on six P0 Decisions (host-contract floor, matrix members, runner shape, state distribution, smoke test scope, rootfs isolation contract).
**Target completion:** TBD
**Depends on:** `.workstream/spack-envs-bootstrap/` (foundation must exist for the smoke test to import torch/jax), `.workstream/uv-in-rootfs/` (rootfs `uv` + `shims/pip` are part of the contract being tested), `.workstream/uv-overlay/` (pip-block and Gate 10b are exercised by negative tests).
**Related docs:** `README.md` (thesis statement), `DESIGN.md` (§§4 path contract, 10 validation, 13 security/isolation), `AGENTS.md` (critical invariants, validation gate sequence), commit `fefc6da` (researcher-first README), [`../INDEX.md`](../INDEX.md).

---

## 1. Goal

Move the README thesis from "documented promise" to "automated contract." After this workstream:

- `scripts/validate-host-contract.sh` formalizes what the outer host must provide (kernel features, glibc floor, bwrap, NVIDIA driver). A researcher landing on an unsupported base image gets `host does not satisfy draccus contract: <missing item>` instead of a mysterious `bwrap: failed to ...`.
- `scripts/validate-rootfs-isolation.sh` formalizes the runtime rootfs boundary: generated rootfs mounted read-only, no baked host `/etc` snapshots, no host home/profile leakage, and only documented writable surfaces.
- A base-image matrix runs the canonical smoke test inside N container base images and asserts the right things happen on each. Hosts that satisfy the contract: smoke test passes. Hosts that don't: contract-check fails with the stated reason. There is no third outcome.
- Negative tests prove the layering enforcement chain actually fires: `pip install torch` rejected with sentinel; synthetic-bad `uv.lock` trips Gate 10b; foundation imports always resolve from `/opt/draccus/view/base-ml/`.
- Code structure is enforced as a product constraint: entrypoints stay thin, reusable logic lives in `lib/`, validation/build workflows live in `scripts/`, generated state stays under `~/.automata/draccus`, and tests stay adjacent to implementations.
- The README "Try it" block and the smoke test are the same source — neither can drift from the other.
- A new "Gate 14: thesis-testable" wires the matrix into `scripts/validate-all.sh` behind an env-var opt-in (the matrix needs container runtime + GPU; running it on every Gate 0 commit is wrong; making it impossible to run from `validate-all.sh` is also wrong).

Net effect: the README's claim — "distraction-free ML dev, dev-prod parity on any base image" — becomes falsifiable. A PR that breaks dev-prod parity on `ubuntu:24.04` fails CI before merge.

## 2. Out of scope

- **Foundation-drift detection at Gate 0** (comparing `envs/base-ml/spack.lock` against running `state/spack/`). Distinct concern, separate workstream candidate.
- **Rootfs-package whitelist Gate 0 check.** Distinct concern, separate workstream candidate.
- **Blocking `python -m pip` via `sitecustomize.py`.** Stays as expert hatch per `.workstream/uv-in-rootfs/design.md §2`. This workstream *tests* that Gate 10b catches it, not that it's blocked at the interpreter.
- **Performance benchmarks.** "Dev-prod parity" means *correctness* parity, not throughput parity, for this workstream. Numerical-output parity across hosts is in scope; wall-clock parity is not.
- **Multi-arch GPU matrices.** `cuda_arch=100` (B200) only, consistent with the foundation pin.
- **Migrating CI off the current runner provider.** This workstream picks one runner shape (decided in P0) and stays with it.
- **A broad top-level test tree.** Tests stay adjacent to the implementation they exercise (`scripts/foo.py` + `scripts/foo_test.py`, `scripts/foo.sh` + `scripts/foo_test.sh`). Shared fixtures stay beside the owning test/script unless they become genuinely cross-cutting.

## 3. Prerequisites

| Requirement | How to verify |
|---|---|
| `uv-in-rootfs` workstream complete (pip-shim + rootfs `uv`) | `.workstream/uv-in-rootfs/tracker.org` shows all phases DONE |
| Gate 0 currently green | `./scripts/validate-static.sh` |
| Container runtime available on the runner host (docker or podman) | `docker info` OR `podman info` |
| At least one GPU runner accessible to CI (B200, `cuda_arch=100`) | Recorded in P0 Decisions |
| A pre-built bundle image OR a way to bootstrap the bundle inside each matrix entry | Decided in P0 |

## 4. Phase decomposition

```
Phase 0  Decisions (host-contract floor, matrix members, runner shape, state-distribution)
Phase 1  scripts/validate-host-contract.sh + scripts/validate-rootfs-isolation.sh
Phase 2  Canonical smoke test (positive + negative assertions; single source of truth)
Phase 3  Matrix harness (container runtime, mount bundle, run smoke test per base image)
Phase 4  Wire into validate-all.sh as Gate 14 (env-var opt-in: DRACCUS_RUN_THESIS_MATRIX=1)
Phase 5  README contract section + tie "Try it" block to the smoke test
```

Phases are sequential. P1 stands alone (useful even without the matrix). P2 is a single source of truth that P3 *consumes* and P5 *references* — do not duplicate.

## 5. Decisions an agent must record (not invent)

Recorded in `tracker.org * Decisions` before P1 starts.

1. **Host-contract floor.** Concrete minimums for each axis. Suggested values, all need user sign-off:
   - Linux kernel ≥ 5.10 (userns + cgroup v2)
   - glibc ≥ 2.31 (Ubuntu 20.04 floor — enough to dynlink rootfs binaries against host driver libs)
   - bwrap ≥ 0.6 (we use `--die-with-parent`, `--unshare-net`, `--ro-bind`)
   - NVIDIA driver ≥ 560 (B200 / Hopper `cuda_arch=100` support floor — verify against current driver release notes)
   - Userns unprivileged: `sysctl kernel.unprivileged_userns_clone=1` OR equivalent CAP_SYS_ADMIN
2. **Matrix members.** Suggested: `ubuntu:20.04`, `ubuntu:24.04`, `debian:bookworm`, `nvidia/cuda:12.x-runtime-ubuntu22.04` (wrong-CUDA-on-host case — the bundle ships its own; this *must* pass), `rockylinux:9` (RHEL family). Explicitly include `alpine:latest` as a *negative* case: musl libc violates the contract; the matrix asserts it fails with the contract-check message, not a stacktrace.
3. **Runner shape.** Options: GitHub Actions self-hosted runner with GPU, internal team-owned GPU node, manual-trigger on the dev host. Affects who can push to main and what the PR-time signal looks like. Affects budget.
4. **State distribution.** Two paths: (a) pre-build a sibling docker image carrying `rootfs/` + `state/spack` + `state/view` (large, ~30-50 GB; built once per Spack-pin bump), or (b) bootstrap-from-scratch inside each matrix entry (slow, ~6-12h per entry; uses live mirrors). Recommend (a) with a periodic rebuild job; (b) as the disaster-recovery path. Record the registry URL + tag schema in this decision.
5. **Smoke test scope.** What exactly the canonical test asserts. Suggested minimum:
   - `torch.cuda.is_available() == True`
   - `torch.cuda.get_device_capability(0) == (10, 0)`
   - `jax.devices()[0].platform == 'gpu'`
   - `numpy.__file__` and `torch.__file__` both under `/opt/draccus/view/base-ml/`
   - `subprocess.run(['pip', 'install', 'torch']).returncode != 0`
   - `validate_uv_layering.sh` against an adjacent bad-lock fixture (for example `scripts/validate_uv_layering_test.bad-uv.lock`) exits non-zero
6. **Rootfs isolation contract.** Production rootfs isolation needs explicit sign-off because it changes bootstrap behavior. Suggested minimum:
   - `rootfs/` is generated and read-only at runtime.
   - Host `/etc/hosts` and `/etc/resolv.conf` are overlaid at launch with `--ro-bind-data`, not copied into the production rootfs.
   - `HOME=/workspace`, `PYTHONNOUSERSITE=1`, and no host user profile paths appear inside the namespace.
   - Writable paths are explicit and finite: `/workspace`, `/tmp`, `/run`, `/opt/draccus/cache`, `/opt/draccus/build`, and documented one-offs like `/var/intel`.
   - NVIDIA driver/device passthrough is the only host runtime escape hatch, and it is audited through `lib/draccus-nvidia-mounts.sh`.

## 6. Invariants honored

Cite, don't redefine. Sources: `AGENTS.md` "Critical invariants", `DESIGN.md` §§4, 10, 13.

- **Two-layer Python model + DO_NOT_SHADOW + pip disabled** (`AGENTS.md` §§1, 2, 6). The matrix *exercises* these invariants — every entry runs the negative tests that prove the chain fires. The matrix does not add new enforcement; it verifies existing enforcement.
- **Canonical prefix contract** (`AGENTS.md` §3). All in-namespace paths used by the smoke test are under `/opt/draccus` or `/workspace`. The matrix's mount-the-bundle step is the standard `draccus-run` contract; the harness does not bind anything new into the namespace.
- **Isolated rootfs** (`AGENTS.md` "Isolated rootfs"). `rootfs/` is generated state; `draccus-run` mounts it read-only; host inputs must be explicit launcher mounts or `--ro-bind-data` overlays with documented purpose.
- **Code structure** (`AGENTS.md` "Code structure"). User-facing entrypoints stay in `bin/`; reusable launcher logic stays in `lib/`; validation/build workflows stay in `scripts/`; tests stay adjacent to the implementations they exercise.
- **draccus-run RO vs draccus-build RW** (`AGENTS.md`). The matrix uses `draccus-run` only — the smoke test is not allowed to mutate the foundation. If a matrix entry needs to bootstrap state, it uses `draccus-build` *outside* the smoke test path, and the smoke test runs against the result.
- **Mandatory `validate-static.sh` after every edit** (`AGENTS.md`).
- **Validation gate sequence** (`AGENTS.md`; `DESIGN.md` §10). Gate 14 takes its place at the end of the ladder, opt-in via `DRACCUS_RUN_THESIS_MATRIX=1`. Gates 0–13 stay sequential and unchanged.

## 7. Necessary complexity

Things an engineer cannot derive from reading individual files alone.

### 7.1 Running bwrap inside a container is the central technical challenge

`bwrap` uses userns. Most container runtimes either (a) don't grant userns to the inner container, (b) grant it only with `--privileged` or `--cap-add SYS_ADMIN` + `--security-opt seccomp=unconfined`, or (c) require sysctl tweaks on the outer host. The matrix harness needs a working combination for *each* matrix entry. The harness must:

- Document the exact `docker run` / `podman run` flags used per base image.
- Probe userns at entry start (`unshare -Ur true` inside the container) and emit a contract violation if it fails — not silently skip.
- Refuse to silently fall back to "skip GPU" when userns is unavailable. Failure here is signal, not noise.

This is why the runner shape (P0 Decision #3) matters: shared CI runners often refuse `--privileged`. A self-hosted runner with relaxed seccomp is the realistic path. Document this in the decision.

### 7.2 GPU access from inside a container running bwrap

Three nested namespaces (host → container → bwrap). Each must pass through the GPU. Concretely:

- Outer container needs `--gpus all` (Docker / NVIDIA container toolkit) or equivalent.
- bwrap mounts driver libs via `lib/draccus-nvidia-mounts.sh`. That code expects host driver libs at `/usr/lib/x86_64-linux-gnu/` etc.; if the *container* base image lacks those paths, the mount needs to discover them at the runner-host level via volume mounts.
- The simplest harness: bind `/usr/lib/x86_64-linux-gnu/` from runner host into the container at the same path, then bwrap finds them as if running natively. Costs one extra `-v` flag per matrix entry.

This is the part where Alpine/musl will fail loudly — the driver libs link against glibc, and binding them into a musl container produces unresolvable symbols. That's a feature: the contract correctly rejects musl.

### 7.3 What "matrix passes" actually means

Three possible per-entry outcomes:

| Outcome | Meaning |
|---|---|
| `pass` | Host satisfies contract AND smoke test passes |
| `contract-rejected` | `validate-host-contract.sh` exits non-zero with a named reason (e.g., "glibc too old"); smoke test never runs; this is **success for that entry** |
| `fail` | Contract passed but smoke test failed, OR contract check fails with an *unexpected* reason (stacktrace, segfault, unrecognized error) |

The matrix CI is green when every entry is `pass` or `contract-rejected`. Any `fail` is a regression. Decoding this distinction matters because Alpine *should* end up `contract-rejected`; if it ever ends up `pass` something is wrong with the contract; if it ends up `fail` something is wrong with the harness.

### 7.4 README ↔ smoke test single source of truth

The README "Try it" block is what researchers copy-paste. Drift between it and reality is the single most common doc-thesis violation in the project's history (cf. the `spack env activate base-ml` lie that commit `fefc6da` fixed). To prevent recurrence:

- Extract the "Try it" commands into `scripts/thesis-smoke-test.py` (or `.sh`).
- The README `Try it` block becomes a one-liner: `./scripts/thesis-smoke-test.py` plus the expected output.
- Gate 0 grep-checks that the README's "Try it" section references the script by name. Researchers reading the README still see the literal commands (printed by the script's own docstring or by `--help`), but the script *is* the authoritative source.

If anyone ever edits the README's "Try it" without touching `scripts/thesis-smoke-test.py`, Gate 0 fires.

### 7.5 State distribution: pre-built bundle image vs. bootstrap-per-run

P0 decision is recorded; the rationale matters here:

- **Pre-built image (recommended).** Build once per foundation-pin bump (Spack SHA or env yaml change). Pushed to an internal registry. Each matrix entry pulls and mounts it as `/data/draccus-bundle`. Matrix runtime: ~5-15 min per entry (mostly bwrap+Python startup). Cost: one image build job per pin bump, ~6-12h wall time on a self-hosted runner.
- **Bootstrap-per-run.** Each matrix entry runs `scripts/bootstrap-rootfs.sh` + `spack install`. Matrix runtime: ~6-12h **per entry**. Useful only as a disaster-recovery check (proves the bundle is reproducible from a clean checkout).

Recommend pre-built image as the default Gate 14 path; a separate (much rarer) `DRACCUS_RUN_REPRODUCIBILITY_MATRIX=1` opt-in for bootstrap-per-run.

### 7.6 Test layout stays adjacent to implementation

This repo should not grow a broad top-level `tests/` tree for production hardening. New tests live beside the implementation they exercise:

- `scripts/thesis-smoke-test.py` gets `scripts/thesis-smoke-test_test.py`.
- `scripts/validate-host-contract.sh` gets `scripts/validate-host-contract_test.sh`.
- `scripts/validate_uv_layering.sh` gets `scripts/validate_uv_layering_test.sh` and any bad-lock fixture beside it, e.g. `scripts/validate_uv_layering_test.bad-uv.lock`.

Only genuinely shared fixtures should move away from the owning script, and that move needs to be justified in the workstream tracker.

### 7.7 Isolated rootfs means generated, read-only, and free of host snapshots

The rootfs is the runtime base, not a source directory. Production acceptance should prove all three properties:

- **Generated:** rootfs contents are reproducible from `scripts/bootstrap-rootfs.sh`, `scripts/uv-version.env`, and the recorded base image or debootstrap decision. Repo-local `rootfs/` may be a symlink to `~/.automata/draccus/...`, but neither form is tracked source.
- **Read-only at run time:** `draccus-run`/`draccus-offline` use `--ro-bind "$DRACCUS_ROOTFS" /`; intentional write points are separate tmpfs/binds. Tests should try representative writes to `/usr`, `/etc`, and `/opt/draccus/view` and assert they fail, while writes to `/workspace`, `/tmp`, cache, and build succeed.
- **No baked host identity:** production rootfs should not carry the launch host's `/etc/hosts`, `/etc/resolv.conf`, home/profile paths, or Nix/profile leakage. Network identity is a live launcher overlay, not rootfs state.

This matters because the product claim is "on top of any base image." If the rootfs accidentally carries this developer host, the claim is not falsifiable.

### 7.8 Negative tests are intentionally fragile across `uv` / `pip` upgrades

Asserting "this command fails with this message" couples the test to wording in upstream tools. We control the pip-shim message (sentinel: `pip is disabled inside draccus`) so that part is stable. But Gate 10b's scanner output and uv's resolver error format can drift. Mitigation:

- Negative tests grep for **sentinel substrings**, not full messages.
- Each sentinel is named, tracked in the adjacent smoke-test sentinel file (`scripts/thesis-smoke-test.sentinels`), and Gate 0 verifies the producer of each sentinel still emits it.

## 8. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| CI runner forbids `--privileged` / userns for bwrap | High on shared runners; Low on self-hosted | P0 Decision #3 picks a runner shape that allows it; document the `docker run` flags |
| GPU passthrough flaky on a given matrix entry | Medium | Probe `nvidia-smi -L` at entry start; treat absence as `contract-rejected`, not `fail` |
| Pre-built bundle image goes stale relative to repo HEAD | Medium | Embed the bundle's committed-rev as an image label; matrix entry asserts label matches expected; nightly rebuild job on pin bumps |
| Matrix run wall-clock kills PR velocity | Medium | Default-skip on PRs (env-var opt-in); run on `main` post-merge and nightly; surface failures via async notification, not blocking merge |
| Alpine (or other musl) starts "working" → contract check has a hole | Low | Test the contract-check against Alpine in P1; treat any *regression* (Alpine moves from `contract-rejected` to `pass`) as a Gate 14 failure |
| README "Try it" + script drift | Low (once Gate 0 enforces) | §7.4 cross-reference; Gate 0 grep |
| Sentinel string drift in upstream tools | Medium | §7.6 sentinel registry; Gate 0 verifies emission |

## 9. Definition of Done (whole workstream)

- All tasks in `tracker.org` marked `DONE`.
- `scripts/validate-host-contract.sh` exists; exits 0 on a satisfying host with a one-line summary; exits non-zero on each named violation with a `host does not satisfy draccus contract: <reason>` message.
- `scripts/validate-rootfs-isolation.sh` exists; verifies rootfs read-only behavior, finite writable surfaces, and absence of baked host identity in production mode.
- `scripts/thesis-smoke-test.py` (or `.sh`) exists; one canonical implementation of the smoke test consumed by README, matrix, and Gate 14.
- Adjacent tests exist for new production scripts, especially `scripts/thesis-smoke-test_test.py`, `scripts/validate-host-contract_test.sh`, and `scripts/validate_uv_layering_test.sh`.
- New production code follows the repo structure rule: thin `bin/` entrypoints, shared `lib/`, workflow `scripts/`, adjacent tests, generated state outside the repo root.
- `scripts/thesis-smoke-test.sentinels` lists every sentinel substring relied on by negative tests; Gate 0 verifies each is still produced.
- `scripts/thesis-matrix.sh` (or equivalent) runs the matrix locally given a runner shape decision; documented invocation in `tracker.org` and in `DESIGN.md`.
- `scripts/validate-all.sh` calls the matrix as Gate 14 when `DRACCUS_RUN_THESIS_MATRIX=1`. Without the env var: Gate 14 prints `[Gate 14] thesis matrix (skipped — set DRACCUS_RUN_THESIS_MATRIX=1)` and continues.
- README "Try it" block calls `scripts/thesis-smoke-test.py` rather than inlining the commands.
- `DESIGN.md §10` documents Gate 14, the matrix outcomes (`pass` / `contract-rejected` / `fail`), and the host-contract floor.
- A successful matrix run output is captured as an artifact in `.workstream/thesis-testable/artifacts/`.
- `* Retrospective` covers: which base images surprised us, did the contract floor need tightening, did GPU passthrough work first try.

## 10. Handoff protocol for agents

1. Read this file end-to-end, then `tracker.org` top-to-bottom.
2. Pick the lowest-numbered `TODO` whose `:DEPENDS:` are `DONE`.
3. Set `IN-PROGRESS`, fill `:OWNER:` + `:STARTED:`.
4. Execute. Append non-trivial command output as `** Log`; large logs and matrix run transcripts go to `artifacts/`.
5. On completion: set `DONE`, fill `:FINISHED:`, list artifacts.
6. If blocked: set `BLOCKED`, write blocker under `** Blocker`, stop. Do not invent workarounds for §6 invariants.

**Don't:**
- Add a base image that's known-incompatible to "make the matrix more impressive." Matrix entries are about coverage of the contract, not breadth for its own sake.
- Skip the negative tests on the grounds that "we know pip is blocked." The whole point of this workstream is that "we know" is not enough.
- Let the README's "Try it" inline commands diverge from `scripts/thesis-smoke-test.py`. §7.4 enforces this; do not weaken the enforcement.

When handing back: `git status` clean or intentional uncommitted state documented under `* Notes`.

## 11. File map for this workstream

```
.workstream/thesis-testable/
├── design.md     this file
├── tracker.org   task tracker
└── artifacts/    matrix run transcripts, contract-check logs, sentinel registry snapshots
```
