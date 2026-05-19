# Workstream: Spack Environments Bootstrap

**Owner:** unassigned
**Status:** Phases 0–5 **DONE**. P4.2 base-ml install completed supervised (`systemd-run --user`; see §7.3); P4.3–P4.4 Gates 6–9 and offline foundation green; `./scripts/validate-all.sh` exit 0 on B200 (2026-05-11, ~137 s wall clock warm cache). Lock snapshots under `.workstream/spack-envs-bootstrap/artifacts/{base-sys,base-ml}.spack.lock`; P5.3 buildcache push skipped (public read-only mirror only).
**Target completion:** TBD
**Related docs:** `DESIGN.md` (§7 design principles, §9 bootstrap, §10 validation), `AGENTS.md` / `CLAUDE.md` (pinned versions, do-not-shadow invariant, critical invariants)

---

## 1. Goal

Take this checkout from a freshly-cloned state with no `state/spack`, no `state/view`, and no `rootfs` to a fully-installed Draccus bundle where:

- `state/view/base-sys/bin/{gcc,clang,cmake,git,...}` resolves cleanly inside `draccus-run`.
- `state/view/base-ml/bin/python` is Python 3.12, importing `torch` (with `cuda.is_available()==True`), `jax`, `numpy`, `scipy` from the Spack view.
- All pinned versions match `AGENTS.md` "Critical invariants" §4: `cuda@13.1.1`, `cudnn@9.17+`, `nccl@2.29+`, `py-torch@2.10.0`, `py-jax/jaxlib@0.9.1`, `python@3.12`, `cuda_arch=100`.
- `scripts/validate-all.sh` passes end-to-end (all 14 gates, GPU host).

## 2. Out of scope

- Curating per-project uv overlays (see `.workstream/uv-overlay/`).
- Building a private buildcache (open question; per-team policy).
- Multi-arch GPU builds (`cuda_arch=100` only).
- Hardening bwrap as a security boundary.

## 3. Prerequisites (Phase 0 — must hold before any agent starts)

| Requirement | How to verify |
|---|---|
| `bwrap` ≥ 0.8 installed and userns permitted | `bwrap --version`; `unshare -Ur true` |
| `docker` + `sudo` (default rootfs path) **or** `debootstrap` (fallback) | `docker info`; `which debootstrap` |
| ≥ 250 GB free under `$DRACCUS_BUNDLE` | `df -h $DRACCUS_BUNDLE` |
| GPU host for Gates 5–13: NVIDIA driver loaded, B200 (SM 10.0) or compatible visible via `nvidia-smi` | `nvidia-smi -L` |
| Outbound network to `github.com`, `pypi.org`, Spack mirror(s) | `curl -fsS https://github.com` |
| Pre-commit installed, Gate 0 currently green | `./scripts/validate-static.sh` |
| For long-running installs on Nix-glibc-hybrid hosts: ability to launch via `systemd-run --user` so the bwrap subtree survives SSH detach (see §7.3) | `systemctl --user status` |

If any item fails: stop, document in `tracker.org`, escalate to owner.

## 4. Phase decomposition

```
Phase 0  Preflight & decisions
Phase 1  Rootfs bootstrap
Phase 2  Spack checkout + mirrors
Phase 3  base-sys env install
Phase 4  base-ml env install
Phase 5  Acceptance & buildcache snapshot
```

Each phase has tasks in `tracker.org` with explicit DoD and the commands to run. Phases are sequential; tasks within a phase may be parallelizable when marked so.

## 5. Key decisions an agent must record (not invent)

Before starting Phase 2, an agent MUST get sign-off (or read recorded decisions) on the four entries below. Each entry in `tracker.org` carries a `SIGN_OFF:` line — `user-approved` or `executor-default`. **Executor-default decisions can be overridden by the user at any later phase; surface them explicitly when handing off.**

1. **Spack pinned commit** — defaults to `develop` are forbidden in production. Record full SHA in `tracker.org`. (Today: `86305d08…`, executor-default to preserve already-reconciled tree.)
2. **Rootfs mode** — `docker` (default, `nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04`) or `debootstrap` (Debian bookworm). Affects `/usr/local/cuda` availability. (Today: docker, executor-default.)
3. **Buildcache mirror URL(s)** — public Spack mirror, internal mirror, or none. Affects build time massively (10× speedup with hits). (Today: `https://mirror.spack.io`, executor-default; team-internal mirror would require user sign-off.)
4. **CPU target** — `x86_64_v3` (current default in `envs/*/spack.yaml`) or `icelake`/`sapphirerapids`. Changes microarch tuning across the whole graph. (Today: `x86_64_v3`, executor-default; any change requires user approval AND editing `envs/*/spack.yaml`.)

Sign-off semantics: an executor-default decision is acceptable for the current run, but escalate before changing one (e.g., bumping Spack SHA or switching CPU target).

## 6. Invariants honored

This workstream **cites** the core invariants; it does not redefine them. Authoritative sources: `AGENTS.md` "Critical invariants" and `DESIGN.md` §§6–8. Honored here:

- **Pinned versions** (`AGENTS.md` "Critical invariants" §4). `cuda@13.1.1`, `cudnn@9.17+`, `NCCL 2.29+`, `py-torch@2.10.0 +cuda +cudnn +nccl ~magma +distributed cuda_arch=100`, `py-jax@0.9.1`, `py-jaxlib@0.9.1 +cuda cuda_arch=100`, `python@3.12`, `TORCH_CUDA_ARCH_LIST=10.0`. P4.1 grep enforces every pin; any drift → BLOCKED, not "make it work".
- **`cuda_arch=100` is sacrosanct** (`AGENTS.md` "Critical invariants" §5). Target hardware is NVIDIA B200 (SM 10.0). Never lower or change without sign-off.
- **Canonical prefix** (`AGENTS.md` "Critical invariants" §3; `DESIGN.md` §4.2). Inside bwrap: every path under `/opt/draccus` or `/workspace`. No host paths (`/data02/home/...`) inside bwrap scripts. `DRACCUS_BUNDLE` resolved via `lib/draccus-env.sh`.
- **draccus-run RO vs draccus-build RW** (`AGENTS.md`; `DESIGN.md` §5). Spack installs use `draccus-build`; all consumers (validate scripts, foundation probes) use `draccus-run`.
- **Do-not-shadow list** (`AGENTS.md` "Critical invariants" §1). `torch`, `jax`, `jaxlib`, `numpy`, `scipy`, `triton`, `nvidia-*`. Authoritative location: `scripts/validate_uv_layering.sh` DO_NOT_SHADOW array. Mirrored in `AGENTS.md` and `scripts/uv_overrides.txt`. Gate 0 enforces three-way sync. This workstream **owns** the Spack-side packages but must not modify the array.
- **No spack.yaml drift** (`AGENTS.md` "What to avoid"). `envs/*/spack.yaml` specs are user-owned. Local concretizer-only tweaks (e.g., `spack config add 'config:build_jobs:16'` in scope) are acceptable; persisting them into the yaml is not.
- **Mandatory `validate-static.sh` after every edit** (`AGENTS.md` "Mandatory: Run after every edit"; pre-commit hook). No commit without Gate 0 green.
- **Validation gate sequence** (`AGENTS.md` "Validation gate sequence"; `DESIGN.md` §10). Gates 0–13 in order; this workstream owns 0–9 and 13 of them.

## 7. Known workarounds

Lessons earned during execution. Each subsection is the **first place** a new engineer should look when something fails the same way. Per-task `:LOGBOOK:` entries in `tracker.org` and the listed `artifacts/*.log` files are evidence, not primary documentation — debug from here, *not* from the logs.

Each entry follows the same shape: **Symptom → Diagnosis → Root cause → Resolution (with file citations) → Verification → When this might no longer be needed → Evidence.**

### 7.1 `llvm@18.1.8` pinned for `py-jaxlib`

- **Symptom.** `py-jaxlib@0.9.1` build fails after ~25–40 minutes (deep inside Bazel/XLA CUDA compilation, typically at `xla/stream_executor/cuda/delay_kernel_cuda.cu.cc`) with ~50–70 errors of two recognizable shapes:
  - `error: no member named 'AnyInvocable' in namespace 'absl'`
  - `error: use of undeclared identifier '__builtin_is_cpp_trivially_relocatable'` (and similar `__builtin_*` not found)
- **Diagnosis trail.** Inspect `artifacts/p4.2-install-resume.log` (the failing attempt). The errors come from NVCC's *host* compile pass — NVCC delegates host C++ to whatever compiler Spack selected for `%c,cxx=...` on `py-jaxlib`. `spack spec py-jaxlib` on the broken concretization showed `%c,cxx=clang@22.1.3`. `clang --version` inside that spec resolves to llvm@22; its libc++ headers ship Abseil-style `AnyInvocable` and the new `__builtin_is_cpp_trivially_relocatable` that NVCC's C++ front-end has not learned yet.
- **Root cause.** `py-jaxlib`'s `package.py` declares "Clang is the only acceptable compiler" on Linux (it builds via Bazel with `--config=cuda`). The Spack concretizer is free to pick *any* `llvm` version that exposes a clang; the most recent (`llvm@22.1.3` at the pinned Spack SHA) is picked by default. NVCC for CUDA 13.1 does not yet support the C++23-ish builtins emitted by clang@20+. Result: every translation unit that pulls libc++ headers fails to compile.
- **Resolution.**
  1. Pin `llvm@18.1.8 +clang +lld %gcc@13.3.0` in `envs/base-sys/spack.yaml:45` (under `definitions:` → root specs). The pin comment at `envs/base-sys/spack.yaml:44` records the rationale verbatim.
  2. Mirror the pin in `envs/base-ml/spack.yaml:56` (`packages:` → `llvm:` → `require: '@18.1.8'`) so `concretizer: unify: true` propagates the same compiler across both envs. Comment at `envs/base-ml/spack.yaml:58` matches.
  3. After `base-sys` installs llvm@18, register the produced clang into Spack's compiler database from inside `draccus-build`:
     ```bash
     . /opt/draccus/spack/share/spack/setup-env.sh
     spack env activate base-sys
     spack compiler find $(spack location -i llvm@18.1.8)/bin
     ```
     Without this step, `base-ml` concretization will reject `%clang@18.1.8` with `"Only external or concrete compilers can be requested"`.
  4. The base-ml spec then lands as `py-jaxlib@0.9.1 +cuda +nccl ~rocm cuda_arch:=100 %c,cxx=clang@18.1.8` — verifiable by grepping `artifacts/p4.1-concretize.log` for `py-jaxlib`.
- **Verification.** After P4.1 (`spack concretize -f`), `grep '^py-jaxlib' artifacts/p4.1-concretize.log` must show `%c,cxx=clang@18.1.8` (not `clang@22.x`). If it does not, the concretizer did not pick up the pin — re-check both env yamls and re-run `spack compiler find`.
- **When this might no longer be needed.** Either (a) NVCC for a CUDA 13.x point release learns the new C++ builtins (watch CUDA release notes), or (b) jaxlib drops the Abseil/builtins idiom from its CUDA TUs, or (c) a future llvm release ships clang flags to disable the offending builtins on NVCC host-compile passes. Until one of those is true, do **not** bump the llvm pin even if Spack concretizes greener with a newer version.
- **Evidence.** `artifacts/p4-llvm18-base-ml-concretize.log`, `artifacts/p4-llvm18-install.log`, `artifacts/p4.2-install-resume.log` (the failing llvm@22 attempt — see line tail for the Abseil/builtin error block).

### 7.2 `~magma` on `py-torch` (and no standalone `magma` root)

- **Symptom.** `py-torch@2.10.0` build fails during the C++ compile of `aten/src/ATen/native/cuda/linalg/` with preprocessor errors of the form `#error "PyTorch requires MAGMA_VERSION_MINOR < 10"` (exact wording varies by torch micro-release; the macro check on `MAGMA_VERSION_MINOR` is the tell). With CUDA 13 the build also drags `magma@2.9+` into the graph because earlier MAGMA series do not support CUDA 13 properly.
- **Diagnosis trail.** `artifacts/p4.2-magma29-concretize.log` shows the concretizer pulling `magma@2.9.0` as a direct dependency of `py-torch`. Comparing against the `py-torch@2.10.0` `package.py`, the compatibility predicate guards a MAGMA-2.10-incompatible code path that the upstream patch has not yet been backported into the pinned Spack SHA.
- **Root cause.** Three-way version pinch: CUDA 13 wants MAGMA ≥ 2.9; PyTorch 2.10 has a hard-coded ceiling at MAGMA < 2.10; the Spack SHA does not yet carry an upstream patch reconciling them. Waiting for an upstream resolution would have blocked the workstream indefinitely.
- **Resolution.** Drop MAGMA from the foundation entirely — `py-torch` on B200 does not actually need MAGMA at runtime for the workloads in scope (linear algebra paths go through cuBLAS / cuSOLVER / cuSPARSE). Concretely:
  1. `envs/base-ml/spack.yaml:79` adds `~magma` to the `py-torch` packages-level `require:` list (with rationale comment at line 78).
  2. The root spec at `envs/base-ml/spack.yaml:113` carries `~magma` redundantly: `py-torch@2.10.0 +cuda +cudnn +nccl ~magma +distributed ~cusparselt cuda_arch=100 ...`. The redundancy is intentional — readers grepping for `py-torch` see the variant inline.
  3. **No standalone `magma` root spec** — removing it from the spec list also removes it from the install set. (Earlier drafts had `magma@2.9.0` as a root spec; that line is gone.)
  4. `~cusparselt` on the same spec line — cuSparseLT is not on the B200/CUDA-13 fast path either; carrying it adds a build with no payoff.
- **Verification.** After P4.1: `grep -E '^(py-torch|magma) ' artifacts/p4.1-concretize.log` must show `py-torch@2.10.0 ... ~magma` and **no** `magma@` lines (neither as a root nor as a dependency). If `magma` reappears as a transitive dep of something else (e.g. some scientific package), file a blocker — do not silently let it back in.
- **Caveat the engineer must know.** Any future workload that needs MAGMA-style mixed-precision dense LA on GPU (e.g. some legacy SciML kernels) will *not* find it. Document that as a separate consumer requirement and revisit the variant only with user sign-off.
- **When this might no longer be needed.** Either (a) PyTorch raises the ceiling to `MAGMA_VERSION_MINOR < 11`, or (b) Spack backports an upstream patch reconciling them, or (c) the team picks a CUDA-12-based base (out of scope per `cuda_arch=100` invariant).
- **Evidence.** `artifacts/p4.2-magma29-concretize.log`, `artifacts/p4.2-magma29-concretize2.log`, `artifacts/base-ml-recreate-conc.log`.

### 7.3 bwrap long-install survival on Nix-glibc hybrid hosts

- **Symptom.** Two distinct deaths:
  1. `./bin/draccus-build bash -lc 'spack install'` launched from an interactive shell dies the moment the SSH session disconnects, even with `tmux new -d`. The `spack install` PID is gone from `ps`; `artifacts/p4.2-install.log` ends mid-build with no error.
  2. Variant on Nix-managed hosts: the install never starts. Stderr shows `bash: /lib/x86_64-linux-gnu/libc.so.6: version 'GLIBC_2.38' not found`, or `bwrap: execvp bash: No such file or directory`, before any Spack output appears.
- **Diagnosis trail.** `bin/draccus-build:74` and `bin/draccus-run:84` both invoke `bwrap --die-with-parent` — by design, the bubblewrap subtree is killed when the launching process exits, so an SSH session ending kills the install. Separately, on hosts where the user's interactive shell is Nix-managed (e.g. `~/.nix-profile/bin/bash` first on `PATH`), the rootfs `/usr/bin/bash` invoked inside bwrap mismatches the loaded glibc when host-side environment variables (notably `LD_LIBRARY_PATH` pointing into `~/.nix-profile/lib`) leak through.
- **Root cause.** `--die-with-parent` is correct (it prevents leaking the namespace when a user `Ctrl-C`s an interactive run); the install path needs a parent that genuinely outlives SSH. Separately, `bash -lc` re-enters the user's host profile inside bwrap, which is the wrong thing to do for a fully-bundled bootstrap.
- **Resolution.** Three-part harness, all checked into `.workstream/spack-envs-bootstrap/artifacts/`:
  1. **`p4.2-host-launcher.sh`** — runs on the host *outside* bwrap. Sources `$HOME/.nix-profile/etc/profile.d/nix.sh` (if present) so the Nix profile is established cleanly before any subshell, then `exec`s `bin/draccus-build` with the prepared environment.
  2. **`systemd-run --user --scope`** — wrap the launcher invocation:
     ```bash
     systemd-run --user --scope --unit=draccus-p4.2 \
       .workstream/spack-envs-bootstrap/artifacts/p4.2-host-launcher.sh
     ```
     The `systemd --user` manager owns the resulting scope, so SSH detach (which kills the user's login session) does **not** kill the scope. `--die-with-parent` is now bound to the scope, which is the right parent.
  3. **Nested `bash --noprofile --norc -c '<spack-install-cmd>'`** inside the inner shell (`artifacts/p4.2-inner.sh`, then `artifacts/p4.2-spack-install.sh`). `bash -lc` would re-source `/etc/profile` and the user's `~/.bashrc` *inside the namespace*, which pulls in random PATH/LD bits from the host. `--noprofile --norc` prevents both. The innermost script emits `[P4.2] spack_exit=<rc>` on `EXIT` so the babysit log unambiguously records completion.
- **Verification.**
  - `systemctl --user status draccus-p4.2.scope` shows `active (running)` for the duration of the install.
  - After SSH detach + reconnect: `tail -f .workstream/spack-envs-bootstrap/artifacts/p4.2-babysit-full.log` continues to advance; the scope is still active.
  - On completion the log ends with a line `[P4.2] spack_exit=0`. Any non-zero rc → consult `artifacts/p4.2-spack-install.sh` for the captured failure point.
- **When this might no longer be needed.** If the host is not Nix-managed AND the operator commits to staying attached via `tmux`, parts (1) and (3) become optional and `tmux new -s draccus-p4.2 ./bin/draccus-build …` works. Part (2) — `systemd-run --user --scope` — is still recommended for any install > 1 h because it is independent of any terminal multiplexer's resilience.
- **Evidence.** `artifacts/p4.2-host-launcher.sh`, `artifacts/p4.2-runner.sh`, `artifacts/p4.2-inner.sh`, `artifacts/p4.2-spack-install.sh`, `artifacts/p4.2-babysit-full.log`, `artifacts/p4.2-env-probe.log` (one-shot env dump used to diagnose the GLIBC mismatch).

### 7.4 `finalize_rootfs_overlay` — `/workspace` stub and SONAME shims

- **Symptom.** Three concrete failure shapes on a freshly extracted rootfs:
  1. `./bin/draccus-probe` (Gate 1) exits non-zero with `bwrap: Can't mkdir /workspace: Read-only file system` or `Can't create file /workspace: No such file or directory`.
  2. `./bin/draccus-run` inside the namespace cannot resolve NVIDIA driver libs — `ldconfig -p | grep libcuda` returns empty, even though `find /usr -name 'libcuda.so*'` on the host shows the driver is installed.
  3. On Nix-managed hosts, `ldconfig -p` itself fails inside the namespace with `Cannot mmap /etc/ld.so.cache: Invalid argument` because the host `ld.so.cache` was generated against a non-rootfs glibc.
- **Diagnosis trail.** `scripts/bootstrap-rootfs.sh:37` defines `finalize_rootfs_overlay`; it is called unconditionally at `scripts/bootstrap-rootfs.sh:236` at the end of rootfs construction. Inspecting an older rootfs (pre-`finalize_rootfs_overlay`) shows it lacks `/workspace/` and any SONAME stub directories. Inspecting a fresh rootfs from a current run shows the stubs present.
- **Root cause.** Bubblewrap with `--bind /host/cwd /workspace` requires a mount point to bind onto; a read-only rootfs has no place to create one at mount time. Separately, `lib/draccus-nvidia-mounts.sh` discovers driver libraries on the host and binds them in at fixed inside-namespace paths; if those parent directories do not exist in the rootfs, the bind silently no-ops (or fails noisily on newer bwrap).
- **Resolution.** `finalize_rootfs_overlay` in `scripts/bootstrap-rootfs.sh` does three jobs at rootfs-construction time:
  1. Creates `$DRACCUS_ROOTFS/workspace/` (the bind target — see `bootstrap-rootfs.sh:46`).
  2. Creates SONAME stub directories under `$DRACCUS_ROOTFS/usr/lib/x86_64-linux-gnu/` so the file-level binds in `lib/draccus-nvidia-mounts.sh` have somewhere to land even when host `ldconfig -p` is unusable.
  3. Drops in any rootfs-side configuration the launchers depend on (the exact list is in the function body — keep it in sync if `lib/draccus-nvidia-mounts.sh` grows new bind paths).
- **Verification.** After `./scripts/bootstrap-rootfs.sh`:
  ```bash
  test -d rootfs/workspace && echo "workspace stub OK"
  ./bin/draccus-probe              # Gate 1 must exit 0
  ./bin/draccus-run bash -lc 'ls /usr/lib/x86_64-linux-gnu/libcuda.so* 2>&1 | head'
  ```
- **When this might no longer be needed.** Only if the rootfs construction switches to a model where the rootfs itself is read-write at run time (it currently is not — `draccus-run` mounts it RO per `AGENTS.md` invariants). Until then the stubs are mandatory.
- **Evidence.** `artifacts/p0.1-preflight.log` (final Gate 0 pass after stubs are present), `artifacts/bootstrap-rootfs-post-apt-fix.log` (the APT-stage fix sequence that motivated the function), `artifacts/bootstrap-autotools-fix.log`.

### 7.5 `spack buildcache keys` CLI drift on the pinned Spack SHA

- **Symptom.** `spack buildcache keys --list` exits non-zero with `error: unrecognized arguments: --list`. Some older README/recipe snippets call this form; it does not work on Spack `86305d08…`.
- **Root cause.** Between v1.1.x and `develop`, Spack reshuffled the `buildcache keys` subcommand's flags. The current set is the short-flag block `-hitf` (and `--help`); `--list` is gone.
- **Resolution.** Use `spack buildcache keys --install --trust` (no `--list`) for the README mirror-trust bootstrap. To enumerate trusted keys after installation, use `spack gpg list --trusted` instead. `spack mirror list` independently confirms the mirror is bound and flagged `[sb]` (source + binary).
- **Verification.** After `spack buildcache keys --install --trust` against `https://mirror.spack.io`:
  ```bash
  spack mirror list | grep -q 'spack-public.*\[sb\]' && echo "mirror OK"
  spack gpg list --trusted | wc -l               # > 0 expected
  ```
- **When this might no longer be needed.** When/if Spack restores `--list` or stabilises the keys subcommand. Re-check on every Spack SHA bump; if the SHA-decision changes, re-verify this section before P2.2.
- **Evidence.** `artifacts/p2.2-mirror.log`.

### 7.6 `state/view/base-sys` broken symlink + GCC/git externals

- **Symptom.** Subsequent `./bin/draccus-build` invocations (after an earlier partial install) fail at the launcher's `mkdir -p` step on `state/view/base-sys/...` with `File exists` (because the path is a dangling symlink, not a real directory). Separately, `validate-base-sys.sh` reports `gcc` missing from `state/view/base-sys/bin/` even when `gcc@13.3.0` is installed.
- **Diagnosis trail.** Spack's view-management generates symlinks; if a view rebuild is interrupted (e.g. by §7.3 SSH death), some symlinks point at paths that no longer exist. Stat the entries under `state/view/base-sys/`: dangling links show as red in `ls --color`. For the missing-`gcc` symptom: `which gcc` inside the namespace still works because the rootfs supplies it from `/usr/bin/gcc` — Spack chose not to copy it into the view because it is registered as an external.
- **Root cause.** Two distinct conditions, easy to confuse:
  1. **Dangling view symlinks** — recovery state from an interrupted view rebuild.
  2. **External packages by design** — `envs/common/rootfs-externals.yaml` registers `gcc@13.3.0`, `git@2.43.0`, and `cuda@13.1.1+allow-unsupported-compilers` as `buildable: false` externals at `/usr` and `/usr/local/cuda`. External packages are not linked into the view at all; consumers find them via `PATH` after `spack env activate`, not via the view bin/ directory.
- **Resolution.**
  1. Before re-running `draccus-build` after an interrupted view rebuild: `find state/view/base-sys -xtype l -delete` to clear dangling symlinks. Then `spack env activate base-sys && spack view regenerate` to rebuild the view cleanly. Do **not** `rm -rf state/view/base-sys` — that loses the view metadata.
  2. `scripts/validate-base-sys.sh` queries `PATH` after `spack env activate base-sys` (rather than enumerating `state/view/base-sys/bin/`), which is the correct contract for view+externals.
  3. The externals are recorded in `envs/common/rootfs-externals.yaml`; the comment block in that file documents *why* each external is preferred over a Spack build (gcc: rootfs already provides it; git: avoids a Spack git↔pcre2 subgraph that clashes with LLVM; cuda: see §7.7).
- **Verification.**
  ```bash
  find state/view/base-sys -xtype l        # expect no output
  ./scripts/validate-base-sys.sh           # Gate 3, must exit 0
  spack -e base-sys find -c                # zero uninstalled specs
  ```
- **When this might no longer be needed.** Dangling symlinks: never — Spack view rebuilds are inherently interruptible. The cleanup is permanent operational hygiene. Externals: only if the rootfs stops bundling these toolchains (would require sign-off — changes the Spack/host boundary).
- **Evidence.** `artifacts/p3.3-validate.log`, `envs/common/rootfs-externals.yaml`.

### 7.7 CUDA as an external from the rootfs (NVIDIA `cuda-installer` SEGV under bwrap)

- **Symptom.** When CUDA is left buildable, Spack pulls NVIDIA's bundled `./cuda-installer` (the `runfile` extraction path) and the install SEGVs immediately inside `draccus-build` — `cuda-installer` aborts with `Segmentation fault (core dumped)` before producing any toolkit files.
- **Diagnosis trail.** The SEGV is reproducible: every `draccus-build`-driven CUDA build attempt SEGVs at the same place. Running the installer directly on the host (outside bwrap) succeeds. The difference is the bubblewrap+userns environment — `cuda-installer` makes assumptions about the namespace/uid setup that bwrap-with-userns violates.
- **Root cause.** NVIDIA's installer touches kernel/namespace features (probably uid mapping or proc introspection) that behave differently inside `bwrap --unshare-all`. We do not own that code path; patching it is not viable.
- **Resolution.** Treat CUDA as a rootfs-provided external. `envs/common/rootfs-externals.yaml` registers:
  ```yaml
  cuda:
    buildable: false
    externals:
      - spec: cuda@13.1.1+allow-unsupported-compilers
        prefix: /usr/local/cuda
  ```
  CUDA enters the rootfs via the docker image (`nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04`, see `scripts/bootstrap-rootfs.sh`). Both `base-sys` and `base-ml` then consume it as an external. The `+allow-unsupported-compilers` variant tells NVCC not to refuse clang@18 on the host-compile pass (necessary for §7.1).
- **Verification.**
  - `ls /usr/local/cuda/bin/nvcc` inside `draccus-run` — must exist.
  - `spack -e base-ml spec cuda` shows `cuda@13.1.1 ... prefix=/usr/local/cuda` (external, not a Spack-built path under `state/spack/opt/spack/`).
  - `p4.1-concretize.log` shows `^cuda@13.1.1+allow-unsupported-compilers` on the `py-torch`/`py-jaxlib`/`nccl` specs.
- **When this might no longer be needed.** Only if NVIDIA's installer becomes bwrap-compatible (unlikely on the timescale of this workstream) or if the team abandons the docker-rootfs path entirely. Until then this is permanent.
- **Evidence.** `artifacts/cuda-single-install.log` (the SEGV reproduction), `envs/common/rootfs-externals.yaml` (the cuda block + its rationale comment).

### 7.8 Validation / tooling — RO Spack, UV in `draccus-run`, JAX cuBLAS soname on CUDA 13

- **Symptom A.** Inside `DRACCUS_OFFLINE=1 ./bin/draccus-run`, `spack env activate base-ml` aborts trying to acquire `transaction_lock` under Spack metadata while `/opt/draccus/spack` is **read-only** in run mode.
- **Resolution A.** For Gate 13 and similar probes, set `PATH=/opt/draccus/view/base-ml/bin:$PATH`, `SPACK_ROOT=/opt/draccus/spack`, **do not** `spack env activate` inside run mode. Applies to maintenance on `scripts/validate_foundation.py` and callers.
- **Symptom B.** `uv` absent inside the namespace (`command not found`) while validations need it for Gate 10/10b.
- **Resolution B.** `DRACCUS_HOST_UV_BIN=<host-path-to-uv-executable>`: `bin/draccus-run` may bind-mount that single file → `/tmp/uv` with `PATH` prefix `/tmp`. Wrapper `bin/draccus-uv` resolves `command -v uv` on the host and exports the variable before exec.
- **Symptom C.** `import jax` segfault / missing CUDA symbol — JAX wheels expect CUDA 12 `libcublas.so.12` soname while the toolkit ships `libcublas.so.13*`.
- **Resolution C.** Re-run `.workstream/spack-envs-bootstrap/artifacts/p4.3-jax-nvidia-stubs.sh` inside `draccus-build` after jaxlib installs; it lays `nvidia/*` shims plus a `libcublas.so.12` symlink chain.
- **Symptom D.** Gate 10b reports torch missing after `uv venv --system-site-packages` despite a healthy unified view.
- **Resolution D.** `uv`'s PEP 517 venv inherits **Spack python's prefix** site-packages, not symlinked view paths — validation prepends `PYTHONPATH=/opt/draccus/view/base-ml/lib/python3.12/site-packages`. The disposable venv lives at `/opt/draccus/cache/draccus-uv-verify/.venv` so `draccus-run` mounts see the same inode across layered script invocations (not `/tmp`).
- **Symptom E.** Gate 4 `grep` for pins misses `cuda_arch:=100` in concretizer output (`:` token).
- **Resolution E.** Scripts use `grep -E 'cuda_arch:?=100'`.
- **Evidence.** `.workstream/spack-envs-bootstrap/artifacts/p4.3-validate.log`, `p4.4-offline.log`, `p5.1-validate-all.log`, `artifacts/p5.2-lock-snapshot.log`.

## 8. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| `py-torch` build time (~6–12 h without cache) | High | Configure buildcache mirror in Phase 2; if no mirror, launch via §7.3 harness so the install survives detach |
| Concretizer fails on `cuda_arch=100` not in package's known list | Medium | Use pinned recent Spack commit (≥ 2026-Q1); attach concretize log to tracker |
| Rootfs missing `/usr/local/cuda` (docker mode pulls wrong tag) | Medium | Verify `ls rootfs/usr/local/cuda*/bin/nvcc` after Phase 1 |
| NVIDIA driver libs not auto-discovered by `lib/draccus-nvidia-mounts.sh` | Medium | Run `bin/draccus-probe` (Gate 1); on Nix-glibc hosts see §7.4 |
| `intel-oneapi-mkl` download requires Intel licence acceptance prompt | Low | Pre-accept via mirror config; substituting `openblas` requires user approval |
| Build OOM at 32 parallel jobs | Low | Lower to `build_jobs: 16` via `spack config add` in env scope (NOT in `envs/*/spack.yaml`) |
| **MAGMA / py-torch version conflict (CUDA 13)** | **Happened in this run** | `~magma` on `py-torch` and drop standalone MAGMA root; see §7.2 |
| **llvm / NVCC microarch incompatibility for jaxlib XLA** | **Happened in this run** | Pin `llvm@18.1.8` in `base-sys`; concretizer-unify propagates to base-ml; see §7.1 |
| **Host-glibc heterogeneity (Nix profile) kills detached install** | **Happened in this run** | `systemd-run --user` harness with explicit Nix profile sourcing; see §7.3 |

## 9. Definition of Done (whole workstream)

- All tasks in `tracker.org` marked `DONE`.
- `./scripts/validate-all.sh` exits 0 on a GPU host (all 13 gates).
- `./scripts/validate-static.sh` exits 0 (Gate 0).
- `state/spack.commit` file records the pinned Spack SHA.
- `tracker.org` `* Decisions` section complete; every entry has `SIGN_OFF` set; executor-defaults explicitly user-confirmed before close.
- `tracker.org` `* Retrospective` written (≥ 3 bullets minimum), and: **one bullet per §7 Known workaround** confirming whether it stayed needed at completion, plus any new workaround discovered during P4.2–P5.
- `§7 Known workarounds` in this file is current with any new entries from the retrospective.

## 10. Handoff protocol for agents

When an agent picks up work:

1. Read this file end-to-end (especially §6 invariants and §7 known workarounds).
2. Read `tracker.org` top-to-bottom.
3. Pick the lowest-numbered `TODO` task whose `:DEPENDS:` are `DONE`.
4. Set status to `IN-PROGRESS`, fill in `:OWNER:` and `:STARTED:`.
5. Execute. Append non-trivial command output as `** Log` or in a `:LOGBOOK:` drawer. Large logs go under `artifacts/` and stay untracked — but mention them in the `artifacts/README.md` index.
6. On completion: set to `DONE`, fill `:FINISHED:`, record artifacts (paths, SHAs).
7. If blocked: set to `BLOCKED`, write the blocking condition under `** Blocker`, stop. **Do not invent workarounds for the invariants in §6.** If you discover a *new* workaround that does not violate §6, document it as a §7 candidate before adopting.

When handing back: leave the working tree clean (`git status` clean) or list intentional uncommitted state in tracker.

## 11. File map for this workstream

```
.workstream/spack-envs-bootstrap/
├── design.md            this file
├── tracker.org          task tracker (org-mode)
└── artifacts/           created during execution
    └── README.md        index of which logs are live-referenced vs archival
```
