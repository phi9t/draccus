---
name: workstream
description: Use the repo's .workstream/ protocol to design, execute, and track any non-trivial feature in the Draccus repo. Invoke whenever the user asks to "start a workstream", "plan a feature", "create a workstream for X", "pick up the <slug> workstream", or otherwise wants to scope multi-step work that doesn't fit in a single edit. Produces a per-feature design.md + tracker.org (org-mode) under .workstream/<slug>/, then drives execution against the tracker.
---

# Workstream skill

Codifies the `.workstream/` protocol defined in `AGENTS.md`. Use this when work is bigger than one file or one PR — anything with phases, decisions, or multi-agent handoff.

## When to invoke

- User says: "create/start a workstream", "let's plan <feature>", "build up tasks for <feature>", "pick up the <slug> workstream", "continue the workstream".
- You're about to start multi-step work that needs decisions recorded or could be handed off.

When in doubt, **propose** a workstream and let the user confirm. Single-file fixes, rename refactors, docs typos → do NOT use this skill.

Reference template (read this first): `.workstream/spack-envs-bootstrap/{design.md,tracker.org}`.

## Two modes

### Mode A — Create a new workstream

1. Pick a slug: kebab-case, descriptive, ≤ 4 words (`add-buildcache-mirror`, `port-to-arm64`). Confirm with the user.
2. Create the directory:
   ```bash
   mkdir -p .workstream/<slug>/artifacts
   ```
3. Write `.workstream/<slug>/design.md` using the template in §"Design template" below. Fill every section — empty placeholders count as TODOs the user must resolve.
4. Write `.workstream/<slug>/tracker.org` using the template in §"Tracker template" below. Phase-decompose the work; each task gets a stable ID (`P<phase>.<n>`), `:DEPENDS:`, and explicit DoD.
5. Pause for user review of `design.md` before any execution. Decisions (pins, mirror URLs, scope cuts) must be recorded under `* Decisions` in `tracker.org` before the dependent task runs.

### Mode B — Continue an existing workstream

1. Read `.workstream/<slug>/design.md` end-to-end. Re-read invariants in `AGENTS.md`.
2. Read `tracker.org` top-to-bottom. Find the lowest-numbered `TODO` whose `:DEPENDS:` are all `DONE`.
3. Edit `tracker.org` to set that task `IN-PROGRESS`, fill `:OWNER:` and `:STARTED:` (ISO-8601 timestamp).
4. Execute. Stream large logs to `artifacts/<task-id>-<step>.log`. Append non-trivial findings or short snippets under the task as `** Log`.
5. On success: set `DONE`, fill `:FINISHED:`, list produced artifacts under `** Artifacts`.
6. If blocked: set `BLOCKED`, write the blocker under `** Blocker`, stop. Do NOT invent workarounds for invariants in `AGENTS.md` §"Critical invariants" — escalate.
7. Hand back with a clean working tree, or list intentional uncommitted state in tracker `* Notes`.

## Hard rules (do not violate)

- Never start a workstream task without `design.md` and `tracker.org` present.
- Never skip the `* Decisions` block — if a downstream task depends on a value (Spack SHA, mirror URL, target arch), it goes under Decisions BEFORE the task runs.
- Never edit `envs/*/spack.yaml` or the `DO_NOT_SHADOW` list from inside a workstream without explicit user approval (per `AGENTS.md`).
- After any edit under `bin/`, `lib/`, `scripts/`, `envs/`, `mise.toml`: run `./scripts/validate-static.sh` before marking the task `DONE`. Tracker DoD must include this whenever such files are touched.
- Promote stable facts to `DESIGN.md` after the workstream completes; `.workstream/` is for in-flight state, not long-term docs.

## Design template (`design.md`)

```markdown
# Workstream: <Title>

**Owner:** <name or unassigned>
**Status:** Not started | In progress | Blocked | Done
**Target completion:** <date or TBD>
**Related docs:** DESIGN.md §<sections>, AGENTS.md §<invariants>

## 1. Goal
One paragraph. What state does the repo / system end up in? How do we know?

## 2. Out of scope
Bullet list. Things people will want to expand into — explicitly excluded.

## 3. Prerequisites (Phase 0)
Table: requirement | how to verify. Includes Gate 0 green, disk, GPU, network as applicable.

## 4. Phase decomposition
Numbered list of phases. Each phase becomes a `* Phase N — Title :phaseN:` section in tracker.org.

## 5. Key decisions an agent must record
Numbered list. Each decision points to a subsection under `* Decisions` in tracker.org.

## 6. Critical invariants
Quote verbatim from AGENTS.md anything that constrains this workstream. Do not paraphrase pinned versions or the do-not-shadow list.

## 7. Risk register
Table: risk | likelihood | mitigation.

## 8. Definition of Done (whole workstream)
Checklist. End with: validate-all.sh (or appropriate subset) green; tracker DONE; retrospective filled.

## 9. Handoff protocol
Point at AGENTS.md §"Workstream protocol" — do not re-state. Add only workstream-specific notes (e.g., "this phase requires the GPU host named X").

## 10. File map
Show the .workstream/<slug>/ tree and what each artifact contains.
```

## Tracker template (`tracker.org`)

```org
#+TITLE: <Title> — Task Tracker
#+STARTUP: overview logdone
#+TODO: TODO(t) IN-PROGRESS(i!) BLOCKED(b@/!) | DONE(d!) WONTFIX(w@/!)
#+PROPERTY: header-args :eval no
#+FILETAGS: :workstream:<slug>:

* Overview
This tracker drives the work described in [[file:design.md][design.md]].
Read design.md §"Critical invariants" and AGENTS.md before claiming a task.

Conventions:
- Each task: :OWNER:, :STARTED:, :FINISHED:, :DEPENDS: properties.
- Logs: nested =** Log= subheading or =:LOGBOOK:= drawer; large output under artifacts/.
- Never edit pinned-version files without user approval (AGENTS.md).

* Decisions
Fill BEFORE the first task that depends on the decision.

** <Decision 1>
   :PROPERTIES:
   :DECIDED_BY:
   :DECIDED_ON:
   :END:
   - Choice:
   - Rationale:

* Phase 1 — <Title> :phase1:
** TODO P1.1 <Action>
   :PROPERTIES:
   :ID:       P1.1
   :OWNER:
   :STARTED:
   :FINISHED:
   :DEPENDS:
   :END:
   DoD: <concrete, observable success condition>
   #+begin_src bash
   # commands; redirect non-trivial output to artifacts/
   ./scripts/validate-static.sh 2>&1 | tee .workstream/<slug>/artifacts/p1.1.log
   #+end_src

* Retrospective
(fill at end)
- Surprises:
- Automate next time:
- Doc gaps:

* Notes
Free-form scratchpad. Promote stable facts to DESIGN.md on close.
```

## Reference example

`.workstream/spack-envs-bootstrap/` is the canonical worked example. Read it before authoring a new workstream — its phase structure (P0 preflight → P1 rootfs → P2 spack → P3 base-sys → P4 base-ml → P5 acceptance), its `:DEPENDS:` chains, and its Decisions block (Spack SHA, rootfs mode, buildcache mirror, CPU target) demonstrate the expected shape.
