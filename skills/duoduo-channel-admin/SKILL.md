---
name: duoduo-channel-admin
description: "Install, start, stop, inspect, reset, and configure duoduo host-mode channels. Use when the request involves: channel lifecycle (install/list/start/stop/status/logs), Feishu setup card or /setup command, Feishu owner DM / main session / FEISHU_BOT_OWNER configuration, the 'main session is locked' refusal, stale card error, resetting a bound Feishu chat, WeChat QR login or packaging, ACP editor integration, channel descriptor editing (kind vs instance). Also trigger for Chinese: 拉起 feishu 通道, 拉起微信 channel, 配置 channel 提示词, 改 stdio 的 workspace, 查看 channel 状态, 飞书机器人怎么配, 设置 owner, 清除 session, 重置 channel, v0.5 升级 feishu 安全."
---

# Duoduo Channel Admin

Host-mode channel lifecycle and channel-facing configuration. Route
by kind (Feishu / WeChat / ACP) and by task (install / configure /
diagnose / reset).

## Start with discovery

Before making any change, run the smallest read-only probe:

```bash
duoduo daemon status             # confirm host mode, daemon alive
duoduo daemon config             # resolve kernel_dir, runtime_dir, defaults
duoduo channel list              # see installed plugins + running state
```

When editing a specific channel instance, always inspect the current
descriptor first:

```bash
cat <runtime_dir>/var/channels/<channel_id>/descriptor.md
```

## Route by kind

Each channel kind has its own reference. Load only the one that
matches the request to avoid polluting context with unrelated detail.

- **Feishu** (飞书) → read [references/feishu.md](references/feishu.md).
  Covers install, credentials, v0.5 `/setup` routing matrix, main
  session contract (owner DM auto-spawn), `FEISHU_BOT_OWNER` security
  hygiene, 200340 triage, reset walkthrough, stale-card guard,
  accepted v0.5 limits.
- **WeChat** (微信) → read [references/wechat.md](references/wechat.md).
  Covers install, start, QR login, state-dir resolution.
- **ACP** (编辑器) → read [references/acp.md](references/acp.md).
  Covers install, editor integration semantics.

When the request is "diagnose a misbehaving Feishu channel" and the
symptom isn't obvious, read
[references/diagnose-feishu.md](references/diagnose-feishu.md) — it
walks a decision tree (card errors, /setup refusals, stale history,
stranger access, ownership drift) to the right remediation.

## Configure channel behavior

Descriptor model: **kind-level** for defaults applied to every
channel of a kind; **instance-level** for one specific channel.

- Kind descriptor: `<kernel_dir>/config/<kind>.md`
- Instance descriptor: `<runtime_dir>/var/channels/<channel_id>/descriptor.md`

Editable keys by hand:

- `new_session_workspace`
- `prompt_mode`
- `time_gap_minutes`
- `stream`
- `allowedTools`
- `disallowedTools`
- `additionalDirectories`

v0.5 adds three keys normally written by `channel.spawn` (not hand-
edited): `runtime`, `bound_by`, `bound_at`. See
[references/channel-config-model.md](references/channel-config-model.md)
for the full list and the `new_session_workspace` priority rules.

For frontmatter edits that must preserve Markdown body and comments,
use [scripts/patch_markdown_frontmatter.py](scripts/patch_markdown_frontmatter.py).

## Reset a bound channel

When a channel's descriptor, session, or message history is stale
and the user wants a clean slate:

```bash
bash scripts/reset-feishu-session.sh --channel-id feishu-<chat_id>
duoduo channel feishu stop && duoduo channel feishu start
```

The script calls `duoduo session archive <session_key>` for every
session that references the channel. That RPC moves the session dir +
ingress + outbox records + channel descriptor under
`var/<kind>-archive/` (timestamped, reversible via `mv`). The plugin
restart is mandatory — it caches subscription state in memory.

Read [references/reset-feishu-session.md](references/reset-feishu-session.md)
for what the script cleans and why each piece matters. When users
report "bot quotes old messages after I reset", they hit the reason
this script exists.

## Prompt editing

- The Markdown body of `kernel/config/<kind>.md` is the kind prompt.
- The Markdown body of `descriptor.md` is the instance prompt.
- Instance frontmatter and prompt override kind defaults.
- Preserve bootstrap-seeded guidance comments when possible.

## Operating rules

- Prefer the smallest scope: kind-level for defaults, instance-level
  for a single room or session surface.
- After editing `~/.config/duoduo/.env` channel credentials, restart
  the affected channel process (not just the daemon).
- After installing a new plugin, verify with `duoduo channel list`
  and `duoduo channel <type> status`.
- If a channel fails after credentials, install state, and runtime
  config all look correct, treat it as a likely product or plugin
  issue — see
  [../duoduo-admin/references/issue-reporting.md](../duoduo-admin/references/issue-reporting.md).
- If the request is really about telemetry, cadence, debug logs, or
  Codex, hand off to `duoduo-runtime-admin`.
