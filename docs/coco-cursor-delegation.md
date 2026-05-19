# Cursor ↔ Coco (TraeCLI) delegation

Engineering notes for wiring **Cursor** to **Coco** via the Model Context Protocol (stdio), so agents in this repo can spawn Coco subagents without nesting another Cursor task.

## Goal

Delegate isolated sub-tasks (broad exploration, planning, or parallel investigation) to Coco (`coco mcp serve`). The Coco MCP server exposes an **`Agent`** tool; `subagent_type` selects Coco’s subagent mode (`Explore`, `Plan`, `general-purpose`, etc.).

## Components

| Piece | Role |
|-------|------|
| `.cursor/mcp.json` | Registers the `coco` stdio server: `coco mcp serve` |
| `.cursor/rules/coco-delegation.mdc` | Cursor rule: when/how to call the tool and safety defaults |
| `AGENTS.md` | Short operational summary + Draccus invariants (must be repeated in delegated prompts) |
| `.trae/COCO_MODELS.md` | Optional: model names for TraeCLI; smoke-test with `./scripts/coco-probe-models.sh` when the catalog changes |

## Prerequisites

| Requirement | Verification |
|-------------|----------------|
| `coco` on `PATH` | `command -v coco` |
| Cursor loads project MCP | Open this repo; restart Cursor after changing `.cursor/mcp.json` |

Installing Coco and choosing models are **out of scope** for this doc (user environment).

## MCP configuration

The server entry uses stdio transport only; no host-specific absolute paths belong in the repo.

```json
{
  "mcpServers": {
    "coco": {
      "type": "stdio",
      "command": "coco",
      "args": ["mcp", "serve"]
    }
  }
}
```

In the IDE, the tool may appear as `mcp_coco_Agent` (server key `coco`).

## Delegation contract

When calling **`Agent`**:

- **`description`**: Short (3–5 word) summary.
- **`prompt`**: Fully self-contained instructions (cwd, paths, deliverable, output shape). Subagents do **not** see the parent chat.
- **`subagent_type`**: Prefer **`Explore`** (read-only) or **`Plan`** (planning). Use **`general-purpose`** only when the user explicitly wants writes or command execution delegated outside this session.

For any work that touches this repository, the prompt must state respect for **`AGENTS.md`** invariants: do-not-shadow list, two-layer Python, no host paths inside bwrap scripts, pinned CUDA/torch/jax, `cuda_arch=100`.

## Risks

| Risk | Mitigation |
|------|------------|
| `general-purpose` can modify files | Default to read-only modes; require clear user intent for writes |
| Naming confusion with Cursor builtins | Rule and this doc name the Coco server and `Agent` tool explicitly |

## Out of scope / follow-ups

- Fallback automation under `scripts/` (optional future work).
- Spack pins, DO_NOT_SHADOW, or bwrap layout changes.

## Definition of done (integration)

End-to-end delivery means:

1. `.cursor/mcp.json` defines the Coco stdio server.
2. `.cursor/rules/coco-delegation.mdc` documents usage and defaults.
3. `AGENTS.md` summarizes delegation and points here for detail.
4. `command -v coco` succeeds where developers run Cursor.

## References

- TraeCLI: `coco doc subagents` (subagent semantics).
- Canonical agent rules: `AGENTS.md`.
