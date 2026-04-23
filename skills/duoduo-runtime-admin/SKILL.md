---
name: duoduo-runtime-admin
description: "Manage host-mode duoduo daemon-level settings and diagnostics. Use when the request involves: inspecting daemon status/config/logs, Codex runtime setup (auto-detected from v0.5: install codex + run `codex login`) or sandbox (ALADUO_CODEX_SANDBOX), log verbosity (ALADUO_LOG_LEVEL), telemetry persistence, cadence interval, other ALADUO_* env keys in ~/.config/duoduo/.env, running-daemon diagnostics, or refreshing subconscious partition prompts from a published duoduo tag. Also trigger for Chinese: 启用 codex runtime, 打开 debug log, 关闭 telemetry, 调 cadence 频率, 看看 duoduo daemon 配置, 查 daemon 日志, 升级潜意识, 刷新潜意识, 更新分区提示词, 同步 subconscious, refresh subconscious, update partition prompts. This skill does NOT handle channel-kind settings (Feishu/WeChat/ACP) — those live in duoduo-channel-admin."
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
- `ALADUO_CODEX_SANDBOX` (codex auto-detected from v0.5 onward; no
  enable flag — see codex-runtime reference)

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

## Subconscious Refresh

Partition prompts under `<kernel>/subconscious/` are NOT touched by a
`npm install` upgrade — install merges missing files only, preserving
local edits and agent self-programming. When the user wants the
revised partition prompts shipped with a newer duoduo version, they
must refresh explicitly.

Read [references/subconscious-refresh.md](references/subconscious-refresh.md)
before making any changes. It covers preconditions (clean kernel git
tree, confirm target tag), the diff-before-overwrite discipline, how
to handle user-authored partitions and local edits to shipped
partitions, the commit-as-rollback-point pattern, and why no daemon
restart is required after refresh.

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
