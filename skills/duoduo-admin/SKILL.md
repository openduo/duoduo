---
name: duoduo-admin
description: "Explain and manage a host-mode duoduo installation after onboarding. Use when the user asks how duoduo works, how stdio/daemon/channel/session fit together, where duoduo stores config and state, how to inspect current setup, how to upgrade duoduo itself (including migrating to v0.5), where something lives on disk (kernel_dir, runtime_dir, .env, descriptor.md), how to archive or recover a specific session (`duoduo session archive`, sessions-archive directory, restoring an archived session), or for broad 'configure duoduo' / 'fix my duoduo' requests that haven't narrowed to a specific channel or runtime setting yet. Also trigger for Chinese: 帮我理解 duoduo, duoduo 是怎么工作的, 看看我现在的 duoduo 配置, 帮我管理 duoduo, 升级 duoduo, 升级到 v0.5 要注意什么, duoduo 哪个路径存什么, 归档 session, 删掉 session, 恢复归档 session."
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

"Is there an update?" → check both:

```bash
duoduo --version
npm view @openduo/duoduo version
```

Standard upgrade path (works for minor bumps within the same major):

```bash
npm install -g @openduo/duoduo@latest
duoduo daemon restart
```

The restart matters because the daemon is a detached background
process — installing a newer CLI package does not hot-swap it.

### Crossing major boundaries (including v0.5)

When the upgrade crosses a behavioral boundary (v0.5 added Feishu
main-session semantics and a new trust model for DMs), follow the
full playbook instead of the one-liner above:

Read [references/upgrade-playbook.md](references/upgrade-playbook.md).

To collect the facts the playbook branches on, run the preflight:

```bash
bash scripts/v05-upgrade-preflight.sh
```

The script outputs markdown listing the installed version, daemon
status, channel inventory, Feishu env keys, and descriptor shapes,
then recommends one of Branch B / C / D. It is an **accelerator,
not a required path**: if the script fails to run or the environment
is unusual, the playbook's Step 1 fallback enumerates every probe
the script performs as an individual command so the agent can
reproduce it by hand.

## v0.5 capabilities you should know about

Three new surfaces landed in v0.5 that change how agents and
automation talk to duoduo. Treat them as additions, not rewrites —
bare `duoduo` still works the same way as before.

- **`duoduo onboard`**: dedicated subcommand that runs the wizard
  and exits (never drops into the chat REPL). This is the correct
  entrypoint for any automation or agent call. In non-TTY contexts
  it reads its answers from env vars (at minimum
  `ALADUO_RUNTIME_MODE`, `ALADUO_CLAUDE_AUTH_SOURCE`) instead of
  prompting. If those are missing, it exits with code 2 and prints
  the full env-var recipe on stderr — forward that recipe to the
  caller rather than guessing.
- **`DUODUO_NODE_BIN` env**: when set, the `duoduo` bash wrapper
  uses that absolute path instead of resolving `node` via PATH.
  Use this when a caller environment resets PATH (`bash -lc` in
  agent spawn, GUI managers shipping a private Node runtime, etc.).
  See openduo/duoduo#50 for the full rationale.
- **User-visible drain errors**: when the daemon's internal SDK
  turn fails (most commonly: third-party compatible endpoints that
  don't accept Claude Code's current wire schema), the user now
  sees a text reply prefixed with `[duoduo:drain-error]` instead
  of silence. The message carries the original error and suggests
  `DISABLE_ADAPTIVE=1 DISABLE_THINKING=1 DISABLE_INTERLEAVED_THINKING=1 MAX_THINKING_TOKENS=0`
  in `~/.config/duoduo/.env` as the common workaround.
- **`duoduo session archive <session_key>`**: new subcommand that
  archives every durable artifact of one session in one call
  (session dir, ingress snapshots, outbox records, channel
  descriptor). "Archive" literally — nothing is deleted, everything
  moves to `var/<kind>-archive/` where the operator can `mv` it
  back. Refuses when the target has a live actor; cancel it first
  via `/cancel`. This is the right tool when the dashboard shows a
  session that should no longer exist (e.g. after a channel reset)
  or when you want a clean slate for one specific session without
  touching the rest of the runtime. The
  `reset-feishu-session.sh` script in `duoduo-channel-admin` drives
  this CLI; read that script as a worked example if you need to
  batch-archive per channel.

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
