# bun-browser HTTP API — Grok (`claw-bun-mcp/grok`) Examples

This guide shows how to call **Grok site adapters** from [claw-bun-mcp](https://github.com/clawhubmx/claw-bun-mcp) over the bun-browser daemon HTTP API, without using the CLI.

Adapters live under `~/.bun-browser/claw-bun-mcp/grok/` (install with `bun-browser site update`). Local overrides in `~/.bun-browser/sites/grok/` take priority.

---

## Prerequisites

1. **bun-browser daemon running**

   ```bash
   bun-browser daemon start
   bun-browser daemon status   # CDP connected: yes
   ```

2. **Chrome logged into grok.com** — open once if needed:

   ```bash
   bun-browser open https://grok.com/
   ```

3. **Bearer token** from `~/.bun-browser/daemon.json`:

   ```bash
   export BUN_BROWSER_TOKEN=$(python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.bun-browser/daemon.json')))['token'])")
   export BUN_BROWSER_HOST=http://127.0.0.1:19824
   ```

   Default port is **19824** (`DAEMON_PORT` in `@bun-browser/shared`).

---

## Site HTTP API overview

All site routes require:

```http
Authorization: Bearer $BUN_BROWSER_TOKEN
Content-Type: application/json   # for POST
```

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/site` | List all installed adapters |
| `GET` | `/site/search?q=grok` | Search adapters by name / description / domain |
| `GET` | `/site/info?name=grok/agents` | Adapter metadata (args, example, domain) |
| `GET` | `/site/adapters/grok/agents` | Same as info, path form (supports `/` in name) |
| `POST` | `/site/run` | Run adapter — body `{ "name", "args", "tabId?" }` |
| `POST` | `/site/adapters/grok/agents` | Run by path — body `{ "args", "tabId?" }` |

### Response shapes

**List / search / info** — HTTP 200:

```json
{ "success": true, "adapters": [ ... ] }
{ "success": true, "adapter": { "name", "description", "domain", "args", ... } }
```

**Run success** — HTTP 200:

```json
{
  "success": true,
  "id": "request-uuid",
  "data": { ... adapter output ... },
  "tab": "short-tab-id",
  "seq": 42
}
```

**Run failure** (adapter error, missing args, not logged in) — HTTP 422:

```json
{
  "success": false,
  "id": "request-uuid",
  "error": "Not logged in",
  "hint": "需要先在浏览器中登录 grok.com（X/xAI 账号）",
  "tab": "abc1"
}
```

**Adapter not found** — HTTP 404:

```json
{ "success": false, "error": "adapter \"grok/foo\" not found", "action": "GET /site/list" }
```

The daemon auto-picks a grok.com tab (or opens one) when `domain` is `grok.com`. Pass `"tabId"` in the POST body to target a specific tab short ID from `bun-browser tab list`.

---

## Discover Grok adapters

```bash
curl -s "$BUN_BROWSER_HOST/site/search?q=grok" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" | jq '.adapters[].name'
```

Expected adapters:

| Name | Purpose |
|------|---------|
| `grok/agents` | List Project agents |
| `grok/agent-chat` | Chat inside a Project agent |
| `grok/agent-memory-list` | List agent Personal files |
| `grok/agent-memory-add` | Upload Personal file |
| `grok/agent-memory-remove` | Remove Personal file |
| `grok/chat` | Default Grok chat (no project) |
| `grok/search` | Search chat history |
| `grok/modes` | List model modes |

Inspect one adapter's args:

```bash
curl -s "$BUN_BROWSER_HOST/site/info?name=grok/agent-chat" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" | jq .
```

---

## End-to-end workflow (example agent: **content creator**)

Typical automation flow:

```
grok/agents  →  find agent id
      ↓
grok/agent-memory-list / add  →  manage knowledge files (optional)
      ↓
grok/agent-chat  →  ask questions in project context
```

### Step 1 — List agents and find `content creator`

**POST `/site/run`**

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"grok/agents","args":{}}' | jq .
```

Filter by name:

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"grok/agents","args":{"pageSize":"200"}}' \
  | jq '.data.agents[] | select(.name == "content creator")'
```

Example agent record:

```json
{
  "id": "945081db-b7b3-4b43-91f9-cc655f522f5f",
  "name": "content creator",
  "url": "https://grok.com/project/945081db-b7b3-4b43-91f9-cc655f522f5f",
  "hasInstructions": true,
  "instructionPreview": "building scientific innovative technology business model..."
}
```

Set for later steps:

```bash
export AGENT_ID=945081db-b7b3-4b43-91f9-cc655f522f5f
```

**Path form (equivalent):**

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/adapters/grok/agents" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.data.count'
```

### Step 2 — List Personal files

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"grok/agent-memory-list\",
    \"args\": { \"agent\": \"$AGENT_ID\" }
  }" | jq .
```

Example response:

```json
{
  "success": true,
  "data": {
    "agentId": "945081db-b7b3-4b43-91f9-cc655f522f5f",
    "agentName": "content creator",
    "url": "https://grok.com/project/945081db-b7b3-4b43-91f9-cc655f522f5f",
    "count": 1,
    "files": [
      {
        "fileId": "981c92b6-bd38-410b-86da-5933be298986",
        "fileName": "brand-voice.md",
        "sizeBytes": 2048,
        "mimeType": "text/markdown",
        "uploadTime": "2026-05-22T06:15:00.399Z",
        "url": "https://grok.com/project/945081db-b7b3-4b43-91f9-cc655f522f5f"
      }
    ]
  }
}
```

`fileId` is the Grok **assetId** — use it for remove.

### Step 3 — Upload a Personal file (text)

Provide **exactly one** of `content` (text) or `fileBase64` (binary). Max ~48 MB per file.

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/adapters/grok/agent-memory-add" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"args\": {
      \"agent\": \"$AGENT_ID\",
      \"fileName\": \"brand-voice.md\",
      \"content\": \"# Brand voice\\n\\nTone: bold, scientific, future-oriented.\"
    }
  }" | jq .
```

Upload PDF (binary):

```bash
B64=$(base64 -i ./deck.pdf)
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"grok/agent-memory-add\",
    \"args\": {
      \"agent\": \"$AGENT_ID\",
      \"fileName\": \"deck.pdf\",
      \"fileBase64\": \"$B64\",
      \"mimeType\": \"application/pdf\"
    }
  }" | jq .
```

Success:

```json
{
  "success": true,
  "data": {
    "agentId": "945081db-b7b3-4b43-91f9-cc655f522f5f",
    "fileId": "981c92b6-bd38-410b-86da-5933be298986",
    "fileName": "brand-voice.md",
    "mimeType": "text/markdown",
    "uploadTime": "2026-05-22T06:15:00.399Z"
  }
}
```

### Step 4 — Remove a Personal file

By **fileId** (preferred):

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"grok/agent-memory-remove\",
    \"args\": {
      \"agent\": \"$AGENT_ID\",
      \"fileId\": \"981c92b6-bd38-410b-86da-5933be298986\"
    }
  }" | jq .
```

By **fileName** (must be unique on that agent):

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"grok/agent-memory-remove\",
    \"args\": {
      \"agent\": \"$AGENT_ID\",
      \"fileName\": \"brand-voice.md\"
    }
  }" | jq .
```

### Step 5 — Chat inside the agent

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/adapters/grok/agent-chat" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"args\": {
      \"agent\": \"$AGENT_ID\",
      \"query\": \"Draft a 3-sentence pitch for an AI-native fintech startup.\",
      \"model\": \"fast\",
      \"disableSearch\": \"false\",
      \"newChat\": \"true\"
    }
  }" | jq .
```

Or pass the project URL as `agent`:

```json
{
  "args": {
    "agent": "https://grok.com/project/945081db-b7b3-4b43-91f9-cc655f522f5f",
    "query": "Summarize my brand voice doc and suggest three campaign angles."
  }
}
```

Example success:

```json
{
  "success": true,
  "data": {
    "agentId": "945081db-b7b3-4b43-91f9-cc655f522f5f",
    "agentName": "content creator",
    "query": "Draft a 3-sentence pitch...",
    "answer": "...",
    "conversationId": "5c375edc-a6aa-40f5-bc7c-4f2c866c6b36",
    "url": "https://grok.com/project/945081db-b7b3-4b43-91f9-cc655f522f5f"
  }
}
```

`agent-chat` may take 30–90 seconds; the daemon command timeout is 15 minutes by default — for long replies, ensure the adapter completes within that window or increase `COMMAND_TIMEOUT` at build time.

---

## All Grok adapters — HTTP reference

### `grok/agents` — list Project agents

| Arg | Required | Default | Description |
|-----|----------|---------|-------------|
| `pageSize` | no | `100` | Max projects to fetch |
| `includeShared` | no | `false` | Include shared projects |
| `includeEmpty` | no | `false` | Include unnamed empty projects |

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/adapters/grok/agents" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args":{"pageSize":"200","includeShared":"true"}}' | jq '.data.agents | length'
```

---

### `grok/agent-chat` — chat in a Project

| Arg | Required | Description |
|-----|----------|-------------|
| `agent` | yes | UUID or `https://grok.com/project/{uuid}` |
| `query` | yes | Prompt |
| `model` | no | `fast`, `auto`, or `expert` |
| `disableSearch` | no | `true` / `false` |
| `newChat` | no | `true` / `false` — new conversation in project |

---

### `grok/agent-memory-list` — list Personal files

| Arg | Required | Description |
|-----|----------|-------------|
| `agent` | yes | Agent UUID or project URL |

---

### `grok/agent-memory-add` — upload Personal file

| Arg | Required | Description |
|-----|----------|-------------|
| `agent` | yes | Agent UUID or project URL |
| `fileName` | yes | Target filename (`notes.md`, `doc.pdf`, …) |
| `content` | one of | Plain-text body |
| `fileBase64` | one of | Base64-encoded bytes |
| `mimeType` | no | Inferred from extension if omitted |

---

### `grok/agent-memory-remove` — remove Personal file

| Arg | Required | Description |
|-----|----------|-------------|
| `agent` | yes | Agent UUID or project URL |
| `fileId` | one of | Asset ID from list |
| `fileName` | one of | Filename (unique on agent) |

---

### `grok/chat` — default Grok chat (no project)

| Arg | Required | Description |
|-----|----------|-------------|
| `query` | yes | Prompt |
| `model` | no | `fast`, `auto`, `expert` |
| `disableSearch` | no | `true` / `false` |
| `newChat` | no | Default `true` |

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/run" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"grok/chat","args":{"query":"Explain quantum computing in one paragraph."}}' \
  | jq '.data.answer'
```

---

### `grok/search` — search chat history

| Arg | Required | Description |
|-----|----------|-------------|
| `query` | yes | Keyword |
| `pageSize` | no | Default `20`, max `60` |
| `pageToken` | no | From previous `nextPageToken` |

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/adapters/grok/search" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args":{"query":"fintech","pageSize":"20"}}' | jq '.data.results[:3]'
```

---

### `grok/modes` — list model modes

No args.

```bash
curl -s -X POST "$BUN_BROWSER_HOST/site/adapters/grok/modes" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.data.available'
```

---

## JavaScript / TypeScript client sketch

```typescript
const HOST = process.env.BUN_BROWSER_HOST ?? "http://127.0.0.1:19824";
const TOKEN = process.env.BUN_BROWSER_TOKEN!;

async function runSite(name: string, args: Record<string, string> = {}) {
  const res = await fetch(`${HOST}/site/run`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ name, args }),
  });
  const body = await res.json();
  if (!body.success) throw new Error(body.error + (body.hint ? `: ${body.hint}` : ""));
  return body.data;
}

// List agents → find content creator → chat
const { agents } = await runSite("grok/agents", { pageSize: "200" });
const agent = agents.find((a: { name: string }) => a.name === "content creator");
const reply = await runSite("grok/agent-chat", {
  agent: agent.id,
  query: "Give me three headline options for a DeFi + AI product launch.",
  model: "fast",
});
console.log(reply.answer);
```

---

## Python client sketch

```python
import json, os, urllib.request

HOST = os.environ.get("BUN_BROWSER_HOST", "http://127.0.0.1:19824")
TOKEN = json.load(open(os.path.expanduser("~/.bun-browser/daemon.json")))["token"]

def run_site(name: str, args: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{HOST}/site/run",
        data=json.dumps({"name": name, "args": args or {}}).encode(),
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        body = json.load(resp)
    if not body.get("success"):
        raise RuntimeError(body.get("error"), body.get("hint"))
    return body["data"]

agents = run_site("grok/agents")["agents"]
agent = next(a for a in agents if a["name"] == "content creator")
files = run_site("grok/agent-memory-list", {"agent": agent["id"]})
print(f"{agent['name']}: {files['count']} personal files")
```

---

## Error handling

Adapters return structured errors in `data` when the browser eval succeeds but the adapter reports failure (`success: false`, HTTP 422):

| `error` | Typical cause | Fix |
|---------|---------------|-----|
| `Not logged in` | No grok.com session in Chrome | Open grok.com and log in |
| `Agent not found` | Bad UUID or no access | Run `grok/agents`, verify `id` |
| `Missing argument: …` | Required `args` omitted | `GET /site/info?name=…` for schema |
| `Missing file payload` | add without `content` or `fileBase64` | Provide exactly one |
| `File not found` | Bad `fileId` / `fileName` | Run `grok/agent-memory-list` |
| `HTTP 403` / anti-bot | Grok blocked the request | Complete verification in browser |

Daemon-level errors:

| HTTP | Meaning |
|------|---------|
| `401` | Invalid or missing Bearer token |
| `404` | Unknown adapter name |
| `503` | Chrome / CDP not connected — run `bun-browser daemon status` |

Every adapter error should include `hint` (human-readable) when available; automation should surface it to the user.

---

## CLI equivalents

| HTTP | CLI |
|------|-----|
| `POST /site/run` `{"name":"grok/agents"}` | `bun-browser site grok/agents` |
| `POST …` `{"name":"grok/agent-memory-list","args":{"agent":"…"}}` | `bun-browser site grok/agent-memory-list <agent>` |
| `POST …` `{"name":"grok/agent-memory-add",…}` | `bun-browser site grok/agent-memory-add <agent> --fileName … --content "…"` |
| `POST …` `{"name":"grok/agent-chat",…}` | `bun-browser site grok/agent-chat <agent> "prompt"` |

More Grok-specific notes: [claw-bun-mcp/grok/GUIDE.md](https://github.com/clawhubmx/claw-bun-mcp/blob/main/grok/GUIDE.md).

---

## Low-level browser API (optional)

Site adapters run as `eval` in a grok.com tab. You can also call browser actions directly:

```bash
curl -s -X POST "$BUN_BROWSER_HOST/command" \
  -H "Authorization: Bearer $BUN_BROWSER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"1","action":"tab_list"}' | jq .
```

Protocol types: `packages/shared/src/protocol.ts`. Prefer `/site/*` for Grok — adapters handle login checks, tab selection, and stable JSON output.
