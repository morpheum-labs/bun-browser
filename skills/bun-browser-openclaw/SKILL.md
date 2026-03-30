---
name: bun-browser-openclaw
description: Turn any website into a CLI command. 36 platforms, 103 commands — Twitter, Reddit, GitHub, YouTube, Zhihu, Bilibili, Weibo, and more. Uses OpenClaw's browser directly, no extra extension needed.
requires:
  bins: bun-browser
allowed-tools: Bash(bun-browser:*)
---

# bun-browser sites — The web as CLI

36 platforms, 103 commands. One-liner structured data from any website using your login state.

**All commands use `--openclaw` to run through OpenClaw's browser. No Chrome extension or daemon needed.**

## Quick Start

```bash
# First time: pull community adapters
bun-browser site update

# See what's available
bun-browser site list

# See which adapters match your browsing habits
bun-browser site recommend

# Run any adapter via OpenClaw's browser
bun-browser site reddit/hot --openclaw
bun-browser site hackernews/top 5 --openclaw
bun-browser site v2ex/hot --openclaw
```

## IMPORTANT: Always use --openclaw

Every `bun-browser site` command MUST include `--openclaw` to use OpenClaw's browser:

```bash
# Correct
bun-browser site twitter/search "AI agent" --openclaw
bun-browser site zhihu/hot 10 --openclaw --json
bun-browser site xueqiu/hot-stock 5 --openclaw --jq '.items[] | {name, changePercent}'

# Wrong (requires separate Chrome extension)
bun-browser site twitter/search "AI agent"
```

## Data Extraction (most common use)

```bash
# Social media
bun-browser site twitter/search "OpenClaw" --openclaw
bun-browser site twitter/thread <tweet-url> --openclaw
bun-browser site reddit/thread <post-url> --openclaw
bun-browser site weibo/hot --openclaw
bun-browser site xiaohongshu/search "query" --openclaw

# Developer
bun-browser site github/repo owner/repo --openclaw
bun-browser site github/issues owner/repo --openclaw
bun-browser site hackernews/top 10 --openclaw
bun-browser site stackoverflow/search "async await" --openclaw
bun-browser site arxiv/search "transformer" --openclaw

# Finance
bun-browser site xueqiu/stock SH600519 --openclaw
bun-browser site xueqiu/hot-stock 5 --openclaw
bun-browser site eastmoney/stock "茅台" --openclaw

# News & Knowledge
bun-browser site zhihu/hot --openclaw
bun-browser site 36kr/newsflash --openclaw
bun-browser site wikipedia/summary "Python" --openclaw

# Video
bun-browser site youtube/transcript VIDEO_ID --openclaw
bun-browser site bilibili/search "query" --openclaw
```

## Filtering with --jq

Use `--jq` to extract specific fields (no need for `--json`, it's implied):

```bash
# Just stock names
bun-browser site xueqiu/hot-stock 5 --openclaw --jq '.items[].name'

# Specific fields as objects
bun-browser site xueqiu/hot-stock 5 --openclaw --jq '.items[] | {name, changePercent, heat}'

# Filter results
bun-browser site reddit/hot --openclaw --jq '.posts[] | {title, score}'
```

## View adapter details

```bash
# Check what args an adapter takes
bun-browser site info xueqiu/stock

# Search adapters by keyword
bun-browser site search reddit
```

## Login State

Adapters run inside OpenClaw's browser tabs. If a site requires login:

1. The adapter will return an error like `{"error": "HTTP 401", "hint": "Not logged in?"}`
2. Log in to the site in OpenClaw's browser:
   ```bash
   openclaw browser open https://twitter.com
   ```
3. Complete login manually in the browser window
4. Retry the command

## Creating New Adapters

Turn any website into a CLI command:

```bash
# Read the guide
bun-browser guide

# Or just tell me: "turn notion.so into a bun-browser adapter"
# I'll reverse-engineer the API, write the adapter, test it, and submit a PR.
```

## All 36 Platforms

| Category | Platforms |
|----------|-----------|
| Search | Google, Baidu, Bing, DuckDuckGo, Sogou WeChat |
| Social | Twitter/X, Reddit, Weibo, Xiaohongshu, Jike, LinkedIn, Hupu |
| News | BBC, Reuters, 36kr, Toutiao, Eastmoney |
| Dev | GitHub, StackOverflow, HackerNews, CSDN, cnblogs, V2EX, Dev.to, npm, PyPI, arXiv |
| Video | YouTube, Bilibili |
| Entertainment | Douban, IMDb, Genius, Qidian |
| Finance | Xueqiu, Eastmoney, Yahoo Finance |
| Jobs | BOSS Zhipin, LinkedIn |
| Knowledge | Wikipedia, Zhihu, Open Library |
| Shopping | SMZDM |
| Tools | Youdao, GSMArena, Product Hunt, Ctrip |
