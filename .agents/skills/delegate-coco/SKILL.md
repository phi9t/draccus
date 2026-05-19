---
name: delegate-coco
description: Delegate a self-contained task to the `coco` CLI (Bytedance TraeCLI) as a one-shot headless subagent. Use when the user asks to "ask coco", "delegate to coco", "run this with coco", "have coco do X", or wants a second-opinion / parallel exploration from a different agent. Produces a single response from coco printed back to the user. Not for interactive multi-turn work — for that, the user should launch `coco` themselves.
---

# Delegate to Coco

`coco` is a separate code agent CLI installed at `/data02/home/philip.yang/.local/bin/coco` (aliases: `traecli`, `trae-agent`, `ta`). Use it as a one-shot subagent: hand it a self-contained prompt, capture the response, surface it to the user.

## When to invoke

- User explicitly says: "delegate to coco", "ask coco", "have coco do X", "run this with coco", "what does coco think".
- You want a parallel/second-opinion run on a contained subtask (research, refactor proposal, code review) without polluting this session's context.

Do NOT invoke for: interactive multi-turn debugging (user should run `coco` themselves), trivial tasks you can do faster inline, or anything the user is already mid-conversation about in this session.

## Invocation pattern

Always run in **print/headless** mode. The agent does not see this conversation — the prompt must be fully self-contained.

```bash
coco --print --output-format text "<self-contained prompt>"
```

Useful flags:

| Flag | When to use |
|------|-------------|
| `-p`, `--print` | Always — non-interactive mode. |
| `--output-format text\|json\|stream-json` | `text` by default. Use `json` when you want to parse the result. |
| `-y`, `--yolo` | Skip tool-permission prompts. Use only when the user has authorised autonomous execution for this delegation. |
| `--allowed-tool Bash --allowed-tool Edit` | Narrow auto-approve list — safer than `--yolo`. Repeatable. |
| `--disallowed-tool Edit` | Force read-only / no-write delegations. |
| `--add-dir <path>` | Extend the writable scope outside cwd. |
| ~~`-w`, `--worktree [name]`~~ | **BROKEN in v0.120.31** — silently no-ops AND ignores the name argument. Coco hallucinates a worktree path in its reply but creates nothing under `.trae/worktrees/`. Pre-create the worktree manually (see Examples) and `cd` into it before invoking coco. |
| `--query-timeout 10m` | Cap runtime. Set this for any non-trivial delegation. |
| `--resume <id>` / `--session-id <id>` | Continue a prior coco session (only if user references one). |
| `-c k=v` | Override config values. |

Sanity check before invoking: `coco doctor` (run only if a previous call failed).

## How to write the delegated prompt

Coco is cold — no chat context, no memory of this session. Brief it like a smart colleague who just walked in:

1. **Goal:** one or two sentences on what to accomplish and why.
2. **Context:** repo location, relevant files (absolute paths), what you've already ruled out.
3. **Constraints:** for Draccus repo, repeat the **critical invariants** from `AGENTS.md` that apply (do-not-shadow list, pinned versions, prefix contract, etc.) — coco will not have read them.
4. **Deliverable shape:** what you want back (a patch? a written analysis? a list of files? bullet points under N words?).
5. **Stop conditions:** what NOT to do (don't commit, don't modify <X>, don't install packages).

Terse "fix the bug" prompts produce shallow, generic work — same failure mode as any subagent.

## Reporting back

After `coco --print` returns:

- Quote or summarise the response for the user — don't just paste raw stdout if it's long. One short paragraph + a link to a saved transcript is usually better.
- If you used `--output-format json`, parse it and surface only the relevant fields.
- For edit-producing delegations, run `git status` / `git diff` and review the changes before claiming success. The summary describes intent, not necessarily reality.
- If coco failed (exit non-zero, timeout, auth error), tell the user the error verbatim and ask whether to retry or fall back to doing it inline.

## Examples

**Quick research delegation (read-only):**
```bash
coco --print --disallowed-tool Edit --disallowed-tool Write --query-timeout 5m \
  "Read /data02/home/philip.yang/draccus/scripts/validate_uv_layering.sh and report (a) the DO_NOT_SHADOW array, (b) where it is invoked. Under 150 words."
```

**Isolated refactor in a worktree** (manual worktree — `-w` is broken in v0.120.31):
```bash
# 1. Create the worktree from the parent shell BEFORE invoking coco.
git worktree add /tmp/coco-wt/refactor-probe -b refactor-probe

# 2. Run coco INSIDE the worktree (cd-then-invoke; do NOT pass --worktree).
(cd /tmp/coco-wt/refactor-probe && coco --print --yolo --query-timeout 15m \
  "$(cat <<'EOF'
You are inside an isolated git worktree of the draccus repo. Execute autonomously; do not ask questions.

Goal: extract the duplicate path-resolution logic from bin/draccus-build and bin/draccus-run into lib/draccus-env.sh.
Constraints (Draccus invariants):
- Do NOT hardcode physical host paths.
- Inside bwrap, paths must be under /opt/draccus or /workspace.
- Run ./scripts/validate-static.sh before declaring done.
Deliverable: a single commit on this worktree branch; print the diff at the end.
If git identity is unset, run `git config user.email phissenschaft@gmail.com && git config user.name phi9t` locally.
EOF
)")

# 3. After coco exits, review from the parent:
git -C /tmp/coco-wt/refactor-probe log --oneline -1
git -C /tmp/coco-wt/refactor-probe diff master..HEAD --stat
```

**Why this pattern**: coco v0.120.31's `-w/--worktree` flag silently does nothing, but coco WILL hallucinate a `.trae/worktrees/<name>` path in its reply, making the failure look like success. Always pre-create the worktree and verify with `git worktree list` afterwards.

**Common failure mode: coco answers the prompt as a chat turn instead of acting.** Symptom: output is a numbered list of clarifying questions or alternatives, no tool calls. Mitigations:
- Add `Execute autonomously; do not ask questions.` to the very first line of the prompt.
- Always pass `--yolo` for autonomous runs (tool-permission prompts in `--print` mode silently produce inaction without it).
- Avoid prompt fragments that look like commands or aliases (coco will try to "find" them). E.g., don't name a worktree `coco-smoke-wt`; call it `smoke` or `feature-x`.
- Keep prompts under ~1500 tokens. Very long prompts in repo cwd appear to trigger Kimi's "let me clarify scope" mode.
