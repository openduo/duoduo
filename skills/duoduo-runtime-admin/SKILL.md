---
name: duoduo-runtime-admin
description: "Manage host-mode duoduo runtime settings and diagnostics. Use when the user asks to inspect or change daemon status, daemon config, daemon logs, Codex runtime enablement, debug log level, telemetry persistence, cadence frequency, or other persistent host-mode settings stored in ~/.config/duoduo/.env. Also trigger for Chinese requests such as 帮我启用 codex runtime, 打开 debug log, 关闭 telemetry, 调 cadence 频率, or 看看 duoduo daemon 配置."
---

# Duoduo Runtime Admin

This skill owns host-mode runtime flags, daemon diagnostics, and persistent
settings in `~/.config/duoduo/.env`.

## Start With Runtime Discovery

1. Confirm host mode with `duoduo daemon status`.
2. Read `duoduo daemon config` before changing persistent settings.
3. Use `duoduo daemon logs` when the user is debugging behavior rather than
   requesting a config change.

Read [references/runtime-settings.md](references/runtime-settings.md) for the
main host-mode knobs and [references/codex-runtime.md](references/codex-runtime.md)
before enabling Codex.

## Persistent Host-Mode Settings

Edit `~/.config/duoduo/.env` with
[scripts/update_host_env.py](scripts/update_host_env.py) instead of ad-hoc
shell edits when you want predictable results.

When the user asks whether duoduo itself is outdated, check:

```bash
duoduo --version
npm view @openduo/duoduo version
```

Then explain whether an update is actually needed before changing anything.

Typical keys:

- `ALADUO_LOG_LEVEL`
- `ALADUO_LOG_RUNNER_THOUGHT_CHUNKS`
- `ALADUO_LOG_SESSION_LIFECYCLE`
- `ALADUO_TELEMETRY_ENABLED`
- `ALADUO_CADENCE_INTERVAL_MS`
- `ALADUO_CODEX_ENABLED`
- `ALADUO_CODEX_SANDBOX`

After changing daemon env settings, run:

```bash
duoduo daemon restart
```

unless the user explicitly asked for an edit only.

## Codex Runtime Scope

Be precise:

- Enabling Codex does not switch all foreground sessions to Codex.
- The current runtime gate enables Codex as an optional backend for jobs.
- Verify `codex` is installed and authenticated before enabling it.

Do not describe Codex enablement as "stdio now runs on Codex" unless the runtime
actually supports that behavior in the inspected version.

## Cadence And Telemetry

- Before changing cadence, explain that a shorter interval increases background
  activity and token usage.
- Disabling telemetry persistence stops JSONL writes but does not necessarily
  suppress every in-process debug log line.
- Use `duoduo daemon config` to inspect the current effective value before
  claiming what the default is on this machine.

## Operating Rules

- Prefer `duoduo daemon config` over stale documentation when values disagree.
- Treat `~/.config/duoduo/.env` as the persistent source of truth in host mode.
- When the user updates the installed `@openduo/duoduo` package, remind them
  that `duoduo daemon restart` is still required because the running daemon is a
  separate background process.
- If runtime behavior still looks wrong after config, restart, and logs have
  been checked, treat it as a likely duoduo bug and use the public issue flow
  from
  [../duoduo-admin/references/issue-reporting.md](../duoduo-admin/references/issue-reporting.md).
- If the request is really about channel install/start/prompt/workspace work,
  hand off to `duoduo-channel-admin`.
