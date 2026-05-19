# Coco (TraeCLI) — curated model names

This file lists **TraeCLI `/model` names** that were **smoke-tested** from this repo with a one-shot non-interactive probe. Exact spelling and case matter: TraeCLI matches `model.name` precisely.

## How to re-run the probe

```bash
./scripts/coco-probe-models.sh
```

- Requires `coco` on `PATH`, working API credentials, and network access.
- Override per-call timeout: `COCO_PROBE_QUERY_TIMEOUT=5m ./scripts/coco-probe-models.sh`
- Raw TSV is written to `.trae/artifacts/` (gitignored); copy a dated `.tsv` if you need to attach evidence to a PR.

**Anti-fallback:** each run uses `--output-format stream-json` and asserts the first `system/init` event’s `model` field equals the requested name (TraeCLI otherwise may fall back to the first configured model without a hard error).

## Last probe (smoke)

| Requested name | `init` model | Name match | Stream result | Wall time (s) |
|----------------|-------------|------------|---------------|---------------|
| GLM-5.1 | GLM-5.1 | yes | success | 34 |
| GLM-5V-Turbo | GLM-5V-Turbo | yes | success | 31 |
| GLM-5 | GLM-5 | yes | success | 33 |
| Gemini-3.1-Pro-Preview | Gemini-3.1-Pro-Preview | yes | success | 34 |
| Gemini-3-Flash-Preview | Gemini-3-Flash-Preview | yes | success | 30 |
| Kimi-K2.6 | Kimi-K2.6 | yes | success | 32 |
| Kimi-K2.5 | Kimi-K2.5 | yes | success | 33 |
| GPT-5.5 | GPT-5.5 | yes | success | 34 |
| GPT-5.4 | GPT-5.4 | yes | success | 31 |
| GPT-5.2 | GPT-5.2 | yes | success | 30 |

- **Prompt:** `Reply with exactly: PING`
- **Per-model timeout:** 3m
- **Probe date (UTC):** 2026-05-10 (artifact timestamp `coco-probe-20260510T230615Z.tsv` when generated locally)

## When to use which (heuristics)

These are **rules of thumb**, not guarantees; check your org’s pricing and latency SLAs.

| Need | Prefer first | Notes |
|------|----------------|------|
| Fast/cheap exploratory search in Coco (`Explore`-style workload) | `Gemini-3-Flash-Preview` | “Flash” tier is usually the speed pick when quality is “good enough”. |
| Deeper reasoning / architecture planning (`Plan`) | `Gemini-3.1-Pro-Preview`, `GPT-5.5`, or `Kimi-K2.6` | Use the wider **GPT-5.x** entries when you want the largest listed context (240k in the `/model` UI). |
| Vision / screenshots | `GLM-5V-Turbo` | The `V` suffix denotes the vision-oriented GLM preset in the picker. |
| General default when unsure | `Kimi-K2.6` | Matches many teams’ “mainline” TraeCLI default; re-probe if your `traecli.yaml` pins another default. |

Within the **GLM-5.x** line and **GPT-5.x** line, pick by internal policy (cost, compliance, or bench). The smoke test only proves routing + a minimal completion, not comparative quality.

## See also

- [`.cursor/rules/coco-delegation.mdc`](../.cursor/rules/coco-delegation.mdc) — when Cursor should delegate to Coco MCP `Agent` / subagents.
- [`AGENTS.md`](../AGENTS.md) — Draccus invariants to paste into delegated prompts.
- TraeCLI manuals: `coco doc model-config`, `coco doc non-interactive-mode`.