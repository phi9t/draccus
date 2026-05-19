# Artifacts Index — spack-envs-bootstrap

This directory holds execution logs and lockfile snapshots from the workstream. Most files are **untracked** in git (see workstream `design.md` §11); this index is the only tracked file so engineers can tell at a glance which logs are still load-bearing vs. archival.

Conventions:

- **Live** — currently referenced from `tracker.org` task entries or `design.md` §7 Known workarounds. Do not delete without updating the citing doc.
- **Archival** — captured from a failed or superseded attempt; preserved as evidence for `§7`. Safe to compress; do not delete while the workstream is open.
- **Snapshot** — lockfile or rc file pinned at a specific task milestone (e.g., `base-ml.spack.lock.p4.1`). Keep for the duration of the workstream; copy to `envs/base-*/spack.lock` is the canonical promotion path.

If you add a new artifact: append a row here, cite it from the relevant task `** Log`, and choose a name that includes the task ID (e.g. `p4.2-foo.log`).

## Phase 0 — Preflight

| File | Status | Notes |
|---|---|---|
| `p0.1-preflight.log` | Live | Cited from `tracker.org` P0.1 `** Log`. Also documents the `finalize_rootfs_overlay` need (design.md §7.4). |

## Phase 1 — Rootfs bootstrap

| File | Status | Notes |
|---|---|---|
| `p1.2-probe.log` | Live | Gate 1 evidence (P1.2). |
| `p1.3-driver-libs.log` | Live | NVIDIA driver libs reachable inside bwrap (P1.3). |
| `bootstrap-rootfs-post-apt-fix.log` | Archival | APT chroot Signed-By repair during rootfs build. Evidence for design.md §7.4. |
| `bootstrap-autotools-fix.log` | Archival | Autotools resolution fix during rootfs build. |

## Phase 2 — Spack + mirrors

| File | Status | Notes |
|---|---|---|
| `p2.2-mirror.log` | Live | `spack buildcache keys --install --trust` CLI-drift evidence (design.md §7.5). |
| `p2.3-paths.log` | Live | Spack canonicality (P2.3). |

## Phase 3 — base-sys

| File | Status | Notes |
|---|---|---|
| `p3.1-concretize.log` | Live | base-sys concretize (P3.1). |
| `p3.2-install.log` | Live | base-sys install (P3.2). |
| `p3.2-install-rerun.log` | Archival | Re-run after concretize tweak; superseded by `p3.2-install.log`. |
| `p3.3-validate.log` | Live | Gate 3 evidence (P3.3). Also documents `state/view/base-sys` broken-symlink fix (design.md §7.6). |
| `base-sys.spack.lock.p3.1` | Snapshot | Lockfile pinned at P3.1 completion. |
| `p4-llvm18-refresh-lock.log` | Archival | Lockfile refresh during the llvm@18 pin work (design.md §7.1). |
| `p4-llvm18-install.log` | Live | `llvm@18.1.8` install (design.md §7.1 evidence). |
| `p4-llvm18-base-ml-concretize.log` | Live | base-ml re-concretize against `clang@18.1.8` (design.md §7.1). |

## Phase 4 — base-ml

| File | Status | Notes |
|---|---|---|
| `p4.1-concretize.log` | Live | Gate 4 pins verified (P4.1). |
| `p4.1-concretize-retest.log` | Archival | Reconcretize after env edits. |
| `base-ml.spack.lock.p4.1` | Snapshot | Lockfile pinned at P4.1 completion. |
| `p4.2-install.log` | Archival | **Stale** — the llvm@22 + jaxlib XLA failure that motivated design.md §7.1. Kept as evidence; do not consume as current state. |
| `p4.2-install-rerun.log` | Live | Current in-flight P4.2 install. |
| `p4.2-install-rerun.pid` | Live | PID of the systemd-run-managed install. |
| `p4.2-install-resume.log` | Archival | Earlier resume attempt; superseded. |
| `p4.2-host-launcher.sh` | Live | `systemd-run --user --scope` launcher (design.md §7.3). |
| `p4.2-runner.sh` | Live | Outer runner sourced by the host launcher. |
| `p4.2-inner.sh` | Live | Inner `bash --noprofile --norc` shell (design.md §7.3). |
| `p4.2-spack-install.sh` | Live | Final inner script emitting `[P4.2] spack_exit=<rc>` on EXIT. |
| `p4.2-babysit-full.log` | Live | Primary tail-able log for the in-flight install. |
| `p4.2-env-probe.log` | Archival | One-shot environment dump from the harness. |
| `p4.2-status-check.log` | Archival | Periodic status checks. |
| `p4.2-resume-attempt.log` | Archival | Earlier failed resume attempt. |
| `p4.2-magma29-concretize.log` | Archival | MAGMA-2.9 concretize attempt before the `~magma` decision (design.md §7.2). |
| `p4.2-magma29-concretize2.log` | Archival | Second MAGMA-2.9 attempt; superseded by `~magma`. |
| `p4.2-install.pid` | Archival | PID of the stale llvm@22 attempt. |
| `intel-mkl-retest.log`, `intel-mkl-retest2.log`, `intel-mkl-retest3.log`, `intel-mkl-retest5.log` | Archival | MKL EULA / retest cycle. Keep for retrospective. |
| `base-ml-recreate-conc.log` | Archival | base-ml env recreate during workaround sequencing. |
| `cuda-single-install.log` | Archival | Stand-alone CUDA install attempt. |
| `debug-cuda-ctty.log`, `debug-cuda-ctty.rc`, `debug_cuda_ctty_runner.py` | Archival | CTTY debugging for the long-install harness (design.md §7.3 precursor). |
| `debug-cuda-pty.log`, `debug-cuda-pty.rc`, `debug_cuda_pty_runner.py` | Archival | PTY debugging for the long-install harness. |
| `debug-sh-x.log` | Archival | Shell tracing artifact. |
| `tar-no-owner.sh`, `wrap-tar.sh`, `tar_shim.log` | Archival | `tar` ownership / shim experiments during rootfs work. |
| `base-sys.spack.lock.p3.1`, `base-ml.spack.lock.p4.1` | Snapshot | Already listed above. |

## Adding a new artifact

1. Run the command, tee to `artifacts/p<phase>.<task>-<purpose>.log`.
2. Cite the file from the relevant task `** Log` in `tracker.org`.
3. Append a row to the matching table here with status `Live`.
4. When the artifact is superseded by a later attempt, change the status to `Archival` rather than deleting.
