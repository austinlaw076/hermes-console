# Codebase KG entrypoint (mandatory)

**Status:** binding for humans and agents  
**Bundle:** Hermes skills `codebase-kg`  
**Clone (this fleet):** `/home/austin/Projects/hermes-console`  
**Human map:** `~/.hermes/wikis/hermes-console/`  
**Domain glossary:** [`../CONTEXT.md`](../CONTEXT.md)  
**Live graph:** `.codegraph/` via CLI `codegraph`

## Rule

For **any** codebase review, study, RCA, refactor, or non-trivial modify on this repo, do this **first** — before grep-driven edits:

1. Load skill **`codebase-kg`** (router).
2. Load leaf **`codegraph-codebase-analysis`** and ensure index freshness.
3. Read **`CONTEXT.md`** (domain terms) + wiki README/architecture if orientation needed.
4. Only then open review/modify skills (`code-review`, `ast-grep`, etc.).

Do **not** treat `docs/ARCHITECTURE.md` alone as SoT — it still reflects an early planned layout; prefer CodeGraph + `~/.hermes/wikis/hermes-console/` + this file.

## Commands

```bash
cd /home/austin/Projects/hermes-console   # or your clone

codegraph status
# if missing/stale:
#   codegraph init && codegraph index
# else:
codegraph sync

codegraph context "<review or change goal>"
codegraph impact "<symbol>" -d 3
codegraph callers "<symbol>"
codegraph callees "<symbol>"
codegraph affected <changed-files...>
```

## Skill bundle (use together)

| Step | Skill | Artifact |
|------|-------|----------|
| Router | `codebase-kg` | pipeline |
| Graph | `codegraph-codebase-analysis` | `.codegraph/` |
| Human map | `code-wiki` | `~/.hermes/wikis/hermes-console/` |
| Domain | `domain-modeling` | `CONTEXT.md` |
| Design vocab (optional) | `codebase-design` | seams/modules language |
| Structural edit | `ast-grep` | AST rewrite |
| Review | `code-review` / `requesting-code-review` | verdict |

## Hotspots (impact discipline)

| Area | Path | Note |
|------|------|------|
| Chat UI | `lib/core/screens/chat_screen.dart` | ~15k+ LOC |
| Turn engine | `lib/core/services/active_chat_service.dart` | ~8k LOC |
| Instances | `lib/core/services/connection_manager.dart` | wide fan-out |
| Gateway facade | `lib/core/services/tui_gateway_client.dart` | many interfaces |
| Bootstrap | `lib/main.dart` | composition root |

## Refresh checklist

After pulling main:

- [ ] `codegraph sync` (or reindex)
- [ ] Wiki SHA in `~/.hermes/wikis/hermes-console/.codewiki-state.json` still sensible; regenerate wiki if architecture shifted
- [ ] `CONTEXT.md` terms still match product language

## Related repo docs

- `docs/UPSTREAM_CONTRACT.md` — ports/endpoints
- `docs/RELEASE_DISTRIBUTION.md` / root `AGENTS.md` — publish boundaries
- `docs/PROJECT_BRIEF.md` — product intent
