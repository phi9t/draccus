# Workstream: Bundle Packaging

**Owner:** unassigned
**Status:** Active - blocked on `single-command-cli` landing the `draccus bundle` namespace.
**Target completion:** Unscheduled
**Related docs:** `docs/training-substrate-roadmap.md`, `.workstream/single-command-cli/design.md`, `DESIGN.md`

## 1. Goal

Make the existing built Draccus foundation bundle easy to package, move, inspect, and install under the shared local state root. The first distribution story is local archive pack/unpack, with schemas shaped so remote channels can be added later.

## 2. Out of scope

- Remote registries and named channels.
- Buildcache publishing.
- Changing pinned foundation versions.
- Auto-bootstrap on first use.

## 3. Prerequisites (Phase 0)

| Requirement | How to verify |
|---|---|
| Single command CLI present | `bin/draccus bundle show --help` |
| Existing built bundle available | `bin/draccus doctor` or equivalent health check passes |
| Sufficient disk for archives | `df -h ~/.automata/draccus` |
| Gate 0 baseline known | `./scripts/validate-static.sh` |

## 4. Phase decomposition

1. Phase 0 - Preflight and archive decisions.
2. Phase 1 - Bundle manifest and show command.
3. Phase 2 - Pack current bundle.
4. Phase 3 - Unpack to default destination.
5. Phase 4 - Docs and validation.

## 5. Key decisions an agent must record

1. Archive format and compression.
2. Manifest schema version.
3. Exact include/exclude set.
4. Overwrite and `--force` behavior.

## 6. Critical invariants

- The packed bundle must preserve the canonical prefix contract: inside bwrap, runtime paths remain `/opt/draccus` and `/workspace`.
- Do not include generated run records, managed projects, caches, build products, or workstream artifacts.
- Do not modify Spack specs, pinned versions, `cuda_arch`, or the do-not-shadow list.
- Any edits to `bin/`, `lib/`, or `scripts/` require `./scripts/validate-static.sh`.

## 7. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Archive accidentally includes huge cache/build state | High | Maintain explicit include/exclude checks and size report. |
| Unpack overwrites a working bundle | Medium | Refuse non-empty destination unless `--force`. |
| Archive is not relocatable | Medium | Test unpack under `~/.automata/draccus/bundles/default` and run doctor. |
| Future registry needs incompatible metadata | Low | Version the manifest and keep identity fields explicit. |

## 8. Definition of Done (whole workstream)

- `draccus bundle pack <archive>` packages the current bundle.
- `draccus bundle unpack <archive>` installs to `~/.automata/draccus/bundles/default` by default and refuses overwrite without `--force`.
- `draccus bundle show --json` reports bundle identity and paths.
- Archive excludes caches, build products, runs, projects, workstream artifacts, and transient files.
- Docs describe local distribution and leave room for future channels.
- Gate 0 passes.

## 9. Handoff protocol

Use `AGENTS.md` workstream protocol. This workstream depends on the single-command CLI namespace. Do not start implementation until `single-command-cli` has landed the `bundle` command structure.

## 10. File map

```text
.workstream/bundle-packaging/
├── design.md
├── tracker.org
└── artifacts/
```
