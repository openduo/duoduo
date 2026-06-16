---
name: duoduo-runtime-admin
description: "Manage host-mode duoduo daemon-level settings, diagnostics, and the `duoduo session` CLI. Use for: daemon status/config/logs and running-daemon diagnostics; Claude/Codex runtime setup (codex auto-detected since v0.5.3: install codex + `codex login`) and default runtime (ALADUO_DEFAULT_RUNTIME); Codex sandbox (ALADUO_CODEX_SANDBOX); log level (ALADUO_LOG_LEVEL); telemetry persistence; cadence interval; other ALADUO_* keys in ~/.config/duoduo/.env; refreshing subconscious partition prompts from a published tag; archiving/pruning the usage ledger (var/usage). Session management: list/inspect sessions, name a session (alias), wake/notify another session by name or key (cross-session orchestration), archive a session. Chinese triggers: 启用 codex runtime, 设置默认 runtime, 打开 debug log, 关闭 telemetry, 调 cadence 频率, 查 daemon 配置/日志, 刷新潜意识, 清理 usage, 给会话起名, 列出会话, 唤醒/通知 session, 归档会话, 跨会话编排. Does NOT handle channel-kind settings (Feishu/WeChat/ACP) — those live in duoduo-channel-admin."
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

- `ALADUO_DEFAULT_RUNTIME`
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

## Runtime Selection

Be precise:

- Claude remains the conservative fallback when no runtime is declared.
- From v0.5.3 onward, Claude and Codex are peer runtimes for channel
  sessions, jobs, and eligible background partitions.
- Runtime selection can happen per actor, per channel kind, or globally with
  `ALADUO_DEFAULT_RUNTIME=codex`.
- Verify `codex` is installed and authenticated before routing work to it.

Do not claim every existing session switches runtime automatically. Existing
sessions keep their stored conversation state until they are rebound, archived,
or naturally start a fresh runtime thread under the effective config.

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

## Usage Ledger Maintenance

`var/usage/<session_key>.jsonl` is append-only with no automatic
retention — long-lived hosts accumulate hundreds of MB. The host
operator (or this skill on request) archives stale files into a
sibling `var/usage-archive/<bucket>/`. The daemon does not need to
restart; it scans `var/usage/` per `usage.get` call.

Read [references/usage-archive.md](references/usage-archive.md) for
the verified `find -mtime +N | xargs mv` recipe, recovery, and the
race-window note.

## Slash Commands (`/compact`, `/undo`, `/model`)

Chat-level history controls landed in v0.5.2: `/compact` shrinks the
context window in place, `/undo [N]` rolls back the last `N`
exchanges. Both work on Claude and Codex runtimes and flow through
the normal channel message pipeline (spine → mailbox → drain), so
the user gets a regular text reply when the command finishes.

Read [references/slash-commands.md](references/slash-commands.md)
for the runtime semantics (synchronous on Codex, deferred on Claude
for `/undo`), troubleshooting when a command appears not to work,
and what to tell a confused user.

`/model` switches the model for a session at runtime without a restart.
Read [references/model-switching.md](references/model-switching.md)
for syntax, Claude vs Codex timing differences, and how to recover
from an invalid model id.

## Session Management (`duoduo session …`)

Four subcommands manage sessions from the CLI (human, agent-via-Bash, or
external script — one entry point):

- `duoduo session list [--kind …] [--named] [--json]` — the live route table.
- `duoduo session alias <key> "<name>"` — give a session a human label, so it
  is legible in `list` and usable as a `notify` target. Unnamed sessions show
  `—` (they are NOT auto-labelled with their key).
- `duoduo session notify <target> -m "<msg>"` — wake a session by key OR alias
  and deliver a source-tagged notification. Only `channel`/`job` targets are
  allowed; the subconscious/kernel plane is isolated and refused.
- `duoduo session archive <key>` — move (never delete) a session's artifacts.

When the user says "name this session X" / "把这个会话叫 X", or wants to wake
one session from another by name, this is the surface. Read
[references/session-cli.md](references/session-cli.md) for full usage, the
isolation boundary, output/`--json` discipline, and the refusal reasons.

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
