# bun-browser Agent Guidelines

## Architecture

```
CLI (packages/cli) ──HTTP──▶ Daemon (packages/daemon) ──SSE──▶ Chrome Extension (extension/)
                                                                      │
                                                                      ▼ chrome.debugger (CDP)
                                                                 User's Real Browser
```

Shared types: `packages/shared/src/protocol.ts`

Adding a new command requires changes in 5 places:
1. `packages/shared/src/protocol.ts` — ActionType + Request + ResponseData
2. `extension/manifest.json` — permissions (if new API needed)
3. `packages/extension/src/background/command-handler.ts` — handler implementation
4. `packages/cli/src/commands/<name>.ts` — CLI command (follow `trace.ts` pattern)
5. `packages/cli/src/index.ts` — import, help text, flag parsing, case routing

The daemon is generic — it routes all commands automatically, no changes needed.

## UX Writing Spec (Agent & Human)

bun-browser has two users: **humans** (direct CLI) and **AI Agents** (bash/MCP). The Agent is the bridge — it reads bun-browser output and translates it for the human. Every text surface must serve both.

### `site list` Descriptions

Formula: `{动作} ({English keywords}: {core return fields})`

```
# Bad — Agent can't match tasks to this
获取雪球股票实时行情

# Good — searchable in both languages, shows what you get back
股票实时行情 (stock quote: price, change%, market cap)
```

### `site info <name>`

Agent's function signature. Expose full @meta:
- `args` with required/optional and description
- `example` with a runnable command
- `readOnly`, `domain`

### JSON Field Naming

Field names ARE the Agent's vocabulary for explaining data to humans.

| Rule | Bad | Good |
|------|-----|------|
| Full English words | `chgPct` | `changePercent` |
| Values include units | `155` | `"1.55%"` |
| Large numbers readable | `177320000000` | `"1.77万亿"` |
| Always include URLs | (missing) | `"url": "https://..."` |
| ISO timestamps | `1710000000` | `"2026-03-15T01:40:31.000Z"` |

### Error Structure

Every error must have three fields:

```json
{
  "error": "HTTP 401",
  "hint": "需要先登录雪球，请先在浏览器中打开 xueqiu.com 并登录",
  "action": "bun-browser open https://xueqiu.com"
}
```

- `error` — technical reason (Agent decides if auto-fixable)
- `hint` — human-readable explanation (Agent relays verbatim when it can't self-fix)
- `action` — executable fix command, nullable (Agent tries this first)

### Post-command Nudges

Every command output that has a natural next step should include a one-line hint:

```
# After site update:
💡 运行 bun-browser site recommend 看看哪些和你的浏览习惯匹配
```

### `--help` Grouping

Group by user intent, most important first:

1. **开始使用** — site recommend, site list, site info, site, guide
2. **浏览器操作** — open, snapshot, click, fill, type, press, scroll
3. **页面信息** — get, screenshot, eval, fetch
4. **标签页** — tab
5. **调试** — network, console, errors, trace, history

### `site recommend`

The primary onboarding command for both humans and Agents:
- Cross-references `history domains` with `site list`
- Shows "available" (with example commands) and "not_available" (with visit counts)
- JSON output structured for Agent capability bootstrap

## Code Conventions

- Commit message: `<type>(<scope>): <summary>` in English
- Types: `fix` / `feat` / `refactor` / `chore` / `docs`
- Chinese for user-facing strings, English for code/comments
- Follow existing patterns: read `trace.ts` before adding a new CLI command
- Build: `bun run build` from repo root
- No tests required for site adapters
