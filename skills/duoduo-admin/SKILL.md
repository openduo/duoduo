---
name: duoduo-admin
description: "Explain and manage a host-mode duoduo installation after onboarding. Use when the user asks how duoduo works, how stdio relates to the daemon and channels, where duoduo stores config and state in host mode, how to inspect the current setup, or broadly asks to configure or understand duoduo before narrowing into channel or runtime changes. Also trigger for Chinese requests such as 帮我理解 duoduo, duoduo 是怎么工作的, 看看我现在的 duoduo 配置, or 帮我管理 duoduo."
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
