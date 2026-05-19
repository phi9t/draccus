---
name: delegate-agent
description: Delegate a self-contained task to the Cursor `agent` CLI as a one-shot headless subagent. Use when the user asks to "ask cursor", "delegate to cursor agent", "run this with the cursor CLI", "have agent do X", or wants a parallel run from Cursor's agent (often for cross-model second opinions like GPT-5 or Sonnet-thinking). Produces a single response printed back to the user. Not for interactive multi-turn work.
---

# Delegate to Cursor Agent

`agent` is Cursor's standalone agent CLI installed at `/data02/home/philip.yang/.local/bin/agent`. Use it as a one-shot subagent: hand it a self-contained prompt, capture the response, surface it to the user. Useful for getting a different *model's* take (e.g., `gpt-5`, `sonnet-4-thinking`) on the same problem.

## When to invoke

- User says: "delegate to cursor agent", "ask the cursor CLI", "have agent do X", "run this with agent", "second opinion from <model>".
- You want a cross-model parallel run on a contained subtask without polluting this session.

Do NOT invoke for: interactive multi-turn work (user runs `agent` themselves), trivial inline tasks, or topics actively under discussion in this chat.

## Invocation pattern

Always run in **print/headless** mode. The agent does not see this conversation — the prompt must be fully self-contained. Headless mode also needs trust:

```bash
agent --print --trust --output-format text "<self-contained prompt>"
```

Useful flags:

| Flag | When to use |
|------|-------------|
| `-p`, `--print` | Always — non-interactive. |
| `--trust` | Required in `--print` to skip the workspace-trust prompt. |
| `--output-format text\|json\|stream-json` | `text` by default. Use `json` when parsing. |
| `--model <id>` | Pick a model: `gpt-5`, `sonnet-4`, `sonnet-4-thinking`, etc. Use `agent --list-models` if uncertain. |
| `--plan` or `--mode plan` | Read-only planning mode (no edits). Default to this for research/proposals. |
| `--mode ask` | Q&A only, read-only. |
| `-f`, `--force` / `--yolo` | Auto-approve all commands. Only when user has authorised autonomous execution. |
| `--sandbox enabled` | Force sandbox even if config disables. Prefer for untrusted code edits. |
| `-w`, `--worktree [name]` | Isolated git worktree (under `~/.cursor/worktrees/<repo>/<name>`). Use for edit-producing delegations. |
| `--worktree-base <ref>` | Base the worktree on a specific branch. |
| `--workspace <path>` | Run against a different directory than cwd. |
| `--approve-mcps` | Auto-approve MCP servers (only if user authorises). |
| `--resume [id]` / `--continue` | Resume a prior session (only if user references one). |

## How to write the delegated prompt

Cursor's agent is cold — no chat context. Brief it like a smart colleague who just walked in:

1. **Goal:** what to accomplish and why, 1–2 sentences.
2. **Context:** repo location, relevant files (absolute paths), what you've already ruled out.
3. **Constraints:** for Draccus, repeat the **critical invariants** from `AGENTS.md` (do-not-shadow list, pinned versions, prefix contract). It has not read them.
4. **Deliverable shape:** patch / analysis / file list / bullets under N words.
5. **Stop conditions:** don't commit, don't modify <X>, don't install packages.

Terse prompts → shallow generic output. Same rule as every other subagent tool.

## Reporting back

After `agent --print` returns:

- Summarise the response — don't paste long raw stdout. A short paragraph plus the saved transcript path is better.
- If `--output-format json`, parse it and surface only the relevant fields.
- For edit-producing delegations, run `git status` / `git diff` (or inspect the worktree) before claiming success — the summary describes intent, not reality.
- On failure (non-zero exit, auth error, model error), report the error verbatim and ask whether to retry or fall back inline.

## Examples

**Read-only second opinion in plan mode (different model):**
```bash
agent --print --trust --plan --model gpt-5 \
  "Read /data02/home/philip.yang/draccus/DESIGN.md sections on the two-layer Python model and the prefix contract. Identify any inconsistencies with /data02/home/philip.yang/draccus/scripts/validate_uv_layering.sh. Under 200 words."
```

**Isolated refactor in a worktree:**
```bash
agent --print --trust --worktree probe-refactor --sandbox enabled --model sonnet-4-thinking \
  "$(cat <<'EOF'
Goal: extract duplicate path-resolution logic from bin/draccus-build and bin/draccus-run into lib/draccus-env.sh.
Constraints (Draccus invariants):
- Do NOT hardcode physical host paths.
- Inside bwrap, paths must be under /opt/draccus or /workspace.
- Run ./scripts/validate-static.sh before declaring done.
Deliverable: a single commit on the worktree branch. Print the final diff.
EOF
)"
```

**Q&A about the codebase (no edits, no plan):**
```bash
agent --print --trust --mode ask --model sonnet-4 \
  "In /data02/home/philip.yang/draccus, which scripts under scripts/ enforce the do-not-shadow invariant? Quote the relevant lines."
```
