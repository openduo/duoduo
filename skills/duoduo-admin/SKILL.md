---
name: duoduo-admin
description: "Explain and manage a host-mode duoduo installation after onboarding. Use when the user asks how duoduo works, how stdio/daemon/channel/session fit together, where duoduo stores config and state, how to inspect current setup, how to upgrade duoduo itself (including migrating to v0.5), where something lives on disk (kernel_dir, runtime_dir, .env, descriptor.md), or for broad 'configure duoduo' / 'fix my duoduo' requests that haven't narrowed to a specific channel or runtime setting yet. Also trigger for Chinese: 帮我理解 duoduo, duoduo 是怎么工作的, 看看我现在的 duoduo 配置, 帮我管理 duoduo, 升级 duoduo, 升级到 v0.5 要注意什么, duoduo 哪个路径存什么."
---

# Duoduo Admin

Use this skill as the host-mode entrypoint for users who do not yet have a clear
mental model of duoduo.

## Start With Discovery

1. Confirm the runtime mode with `duoduo daemon status`.
2. If the runtime is not in host mode, explain that this skill automates
   host-mode operations only and limit container-mode work to inspection unless
   the user explicitly asks for container-specific changes.
3. Read `duoduo daemon config` before making persistent changes. Treat that
   output as the source of truth for paths and active settings.
4. If the daemon is down, start there. If the machine is not onboarded yet,
   explain that the user must finish `duoduo` onboarding first.
5. If the user says something is broken, first decide whether it is local
   misconfiguration, operator error, channel/plugin setup error, or a likely
   duoduo product bug.

## Explain Duoduo In Host-Mode Terms

Keep the explanation concrete and filesystem-first.

- `stdio` is the default direct operator surface after onboarding.
- `duoduo daemon ...` manages the long-lived runtime process.
- `duoduo channel ...` manages installable external channel plugins.
- `~/.config/duoduo/.env` is the persistent host-mode settings file.
- `kernel/config/<kind>.md` stores per-channel-kind defaults and kind prompts.
- `var/channels/<channel_id>/descriptor.md` stores per-channel-instance
  overrides and instance prompts.
- The host daemon is a detached background process. Updating package files alone
  does not replace the running process.
- Re-opening `duoduo` from the same real workspace path re-attaches the same
  stdio session key instead of creating a brand-new conversation surface.

Read [references/host-mode-map.md](references/host-mode-map.md) when the user
needs a fuller explanation of how these surfaces fit together.

## Upgrade And Restart

When the user asks whether an update is available, check both:

```bash
duoduo --version
npm view @openduo/duoduo version
```

Compare the installed version with the latest published npm version.

When the user asks to update duoduo itself in host mode, use this sequence:

```bash
npm install -g @openduo/duoduo@latest
duoduo daemon restart
```

Explain why the restart matters: the daemon is already running as a detached
background process, so installing a newer CLI package does not hot-swap the
existing daemon process.

### Upgrading to v0.5 (Feishu channel semantics change)

v0.5 introduces owner-DM auto-spawn and a `/setup` routing matrix for
the Feishu channel. If the user is upgrading from a pre-v0.5 install
AND has a Feishu channel configured, use /duoduo-channel-admin for detailed instructions, and focus on the
sections "Main session contract" and "Security hygiene" BEFORE making
behavioral changes on their behalf. In particular, warn them that:

- Without `FEISHU_BOT_OWNER` set, any first DM sender is treated as
  owner for that session's auto-spawn (zero-config bootstrap mode).
- `dmPolicy=open` is the default, so combining zero-config with the
  default means strangers who reach the bot can trigger auto-spawn.
- Production configurations should set `FEISHU_BOT_OWNER` and
  `FEISHU_DM_POLICY=allowlist` before exposing the bot broadly.

Pre-v0.5 bindings (descriptors without `bound_by`) continue to work
without migration — their `/setup` routes through the secondary card
path, preserving operator reach.

## Find Problems And Escalate

When the user is reporting a bug or unexpected behavior:

1. Reproduce or at least restate the exact symptom.
2. Inspect the live state with the smallest useful commands, usually
   `duoduo daemon status`, `duoduo daemon config`, `duoduo daemon logs`, and
   any relevant `duoduo channel ... status/logs`.
3. Separate local setup mistakes from probable product defects.
4. If it looks like a duoduo bug or docs gap, prepare a public-safe issue
   summary for `openduo/duoduo`.

Read [references/issue-reporting.md](references/issue-reporting.md) when the
user wants to file an issue or asks you to prepare one.

## Route The Request

- Channel installation, channel lifecycle, Feishu setup, WeChat packaging, or
  channel prompt/workspace changes:
  read [../duoduo-channel-admin/SKILL.md](../duoduo-channel-admin/SKILL.md)
  and let that workflow own the implementation.
- Runtime flags such as Codex, debug logs, telemetry, cadence, or daemon
  diagnostics:
  read [../duoduo-runtime-admin/SKILL.md](../duoduo-runtime-admin/SKILL.md)
  and let that workflow own the implementation.
- Confirmed bug report or docs gap that should be escalated publicly:
  use [references/issue-reporting.md](references/issue-reporting.md).
- Mixed or vague requests:
  explain the mechanism first, then move into the smallest concrete change.

## Operating Rules

- Prefer live inspection over defaults. Use the actual daemon config, actual
  files, and actual channel list before claiming how the system is set up.
- After editing `~/.config/duoduo/.env`, tell the user to run
  `duoduo daemon restart` unless they explicitly asked for an edit-only change.
- When the user asks to "understand duoduo", answer in terms of files,
  commands, and lifecycle rather than abstract architecture jargon.
- Do not pretend a raw Git repository can be installed as a channel plugin.
  Duoduo's channel installer accepts npm package specs or `.tgz` tarballs.
