# Dashboard: Channels & Entities

Enhanced ATC dashboard adding Channels and Entities tabs for operational
visibility into group channels and memory entities.

## What this is

A drop-in replacement for the default dashboard (`bootstrap/dashboard.html`)
that adds:

- **Channels tab** — Global config cards (feishu.md editable, CLAUDE.md read-only) + group channel list with Feishu API-sourced names, status indicators, and editable descriptor.md
- **Entities tab** — Searchable entity list from `memory/index.md`, grouped by section (People/Tools/Services/Projects), with markdown rendering + edit/save
- **Edit/Save** — Optional host-side write API for live editing of config and entity files

## Files

- `dashboard.html` — the dashboard itself (single-file, no build step)
- `refresh-channel-map.py` — generates `channel-id-map.json` from disk scan + Feishu `im/v1/chats/{chat_id}` API
- `save-api.py` — lightweight write API (port 20234, localhost only, path-restricted)

## Install

1. Copy the dashboard into place:
   ```bash
   # Container mode
   docker cp contrib/dashboard/dashboard.html duoduo-openduo:/app/bootstrap/dashboard.html

   # Host mode
   cp contrib/dashboard/dashboard.html bootstrap/dashboard.html
   ```
   The daemon serves this file at `/dashboard`. Takes effect on next page load (no restart needed).

2. (Optional) Generate channel name mapping — requires Feishu credentials:
   ```bash
   # Ensure FEISHU_APP_ID and FEISHU_APP_SECRET are set (from .env or exported)
   cd contrib/dashboard && python3 refresh-channel-map.py
   ```
   Outputs `channel-id-map.json` to the runtime `var/` directory.

3. (Optional) Start save-api for edit/save support:
   ```bash
   nohup python3 contrib/dashboard/save-api.py > /tmp/save-api.log 2>&1 &
   ```
   Runs on port 20234. Restricts writes to approved path prefixes
   (`config/`, `memory/entities/`, `var/channels/`).

## Uninstall

Restore the original dashboard by restarting the container (bootstrap re-seeds
the default), or manually:

```bash
# If you have the source
cp bootstrap/dashboard.html.bak bootstrap/dashboard.html
```

## Dependencies

- Python 3 (for helper scripts only; the dashboard itself is pure HTML/JS)
- Feishu API credentials (`FEISHU_APP_ID`, `FEISHU_APP_SECRET`) — only for `refresh-channel-map.py`
