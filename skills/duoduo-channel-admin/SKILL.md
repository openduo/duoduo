---
name: duoduo-channel-admin
description: "Install, start, stop, inspect, reset, and configure duoduo host-mode channels. Use when the request involves: channel lifecycle (install/list/start/stop/status/logs), Feishu setup card or /setup command, Feishu owner DM / FEISHU_BOT_OWNER configuration, the owner-DM rebind refusal, a second Feishu or Lark app (--instance), a chat forwarded to an existing session (forward / send), asking someone in a Feishu chat to choose, approve or answer (ask, question card, approval card), stale card error, resetting a bound Feishu chat, ACP editor integration, channel descriptor editing (kind vs instance). Also trigger for Chinese: 拉起 feishu 通道, 配置 channel 提示词, 改 stdio 的 workspace, 查看 channel 状态, 飞书机器人怎么配, 设置 owner, 清除 session, 重置 channel, 加一个 Lark 应用, 第二个飞书应用, 把群转给已有会话, 回复转发的群, 发提问卡片, 让群里的人选择, 审批卡片."
---

# Duoduo Channel Admin

Host-mode channel lifecycle and channel-facing configuration. Route
by kind (Feishu / ACP) and by task (install / configure /
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
  Covers install, credentials, v0.5 `/setup` routing matrix, owner DM
  contract (auto-spawn, automatic main-session claim), `FEISHU_BOT_OWNER`
  security hygiene, 200340 triage, reset walkthrough, stale-card guard,
  accepted v0.5 limits.
- **A second Feishu or Lark app** (another tenant, company, or the
  international domain) → read
  [references/feishu-second-app.md](references/feishu-second-app.md):
  named instances, the per-instance env file and secret handover,
  per-instance lifecycle and upgrade.
- **One context across chats and bots** — a chat should be served by a
  session that already exists, a setup-card "Hand to an existing session"
  request reached the main session, or a session must answer a forwarded
  message → read [references/feishu-forward.md](references/feishu-forward.md):
  `forward`, `send`, who may run them, the cold-start flow.
- **Asking someone in a chat** — a session needs a person in a forwarded chat
  or in its own chat to choose, approve or answer before it can go on → the
  same reference, section "Ask someone in a chat": `ask`, `--who`, approvals,
  limits.
- **ACP** (编辑器) → read [references/acp.md](references/acp.md).
  Covers install, editor integration semantics.

Cross-kind conventions — installer package specs, why install is a
pure write-to-disk (a running plugin keeps serving the old code until
an explicit `stop && start`), and the lifecycle verbs — live in
[references/channel-lifecycle.md](references/channel-lifecycle.md).

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
- `prompt_mode` (claude, grok, and pi; refused on an explicit `runtime: codex` job)
- `time_gap_minutes`
- `runtime` (`claude` | `codex` | `grok` | `pi` — pi sessions also need a
  model pointer; see duoduo-runtime-admin's pi-runtime reference). A live
  session is bound to its runtime: `/clear` it before changing this key,
  or its next turn is refused. A value duoduo does not know is refused on
  every turn it would select, never replaced by another runtime. `void` is
  meant for plugins such as tether whose sessions run no model; do not set it
  on an ordinary chat channel — no model runs, and the plugin may send the
  incoming messages back instead of a reply
- `stream`
- `allowedTools` (permission auto-approve — does not extend the tool surface)
- `disallowedTools` (MCP tools only)
- `additionalDirectories`
- `claude.tools` (extra built-in tools unioned onto the fixed
  allowlist core; the built-in surface is allowlist-based)

Two instance-binding keys are normally written by `channel.spawn`
(not hand-edited): `bound_by`, `bound_at`. See
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
