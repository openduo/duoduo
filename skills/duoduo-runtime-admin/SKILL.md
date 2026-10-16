---
name: duoduo-runtime-admin
description: "Manage host-mode duoduo daemon settings, diagnostics, and the `duoduo session` / `duoduo job` / `duoduo spine` CLIs. Use for: daemon status, config, logs; runtime selection (Claude/Codex/Grok/Pi, ALADUO_DEFAULT_RUNTIME); ALADUO_* keys in ~/.config/duoduo/.env; refreshing subconscious prompts; the `duoduo memory` CLI; reading the Spine log; pruning the usage ledger; model profiles for third-party models (context caps, routing, subagent tiers); codex tool trimming; pi compaction sizing; session management (list, alias, notify or wake by name, archive); job lifecycle from the CLI (list, read, archive, interrupt, reschedule). Chinese triggers: 启用 codex/grok/pi runtime, 设置默认 runtime, 打开 debug log, 关闭 telemetry, 调 cadence 频率, 查 daemon 配置/日志, 刷新潜意识, 读 spine, 清理 usage, 给会话起名, 唤醒/通知 session, 归档会话, 归档任务, 打断任务, 让任务再跑一次, 模型 profile, 裁剪 codex 工具, pi 只回一个字. Does NOT handle channel-kind settings (Feishu/ACP) — see duoduo-channel-admin."
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
main host-mode knobs, [references/codex-runtime.md](references/codex-runtime.md)
before enabling Codex, [references/grok-runtime.md](references/grok-runtime.md)
before enabling Grok, and [references/pi-runtime.md](references/pi-runtime.md)
before enabling Pi — its Context and compaction section also covers a pi
session that has started answering with a single character (a filled
context window, not a broken model).

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
- `ALADUO_SPINE_INDEX_RETENTION_DAYS`
- `ALADUO_CODEX_SANDBOX` (codex is auto-detected; no enable flag —
  see codex-runtime reference)

After changing daemon env settings, run:

```bash
duoduo daemon restart -r "changed <setting>"
```

unless the user explicitly asked for an edit only.

## Runtime Selection

Be precise:

- Claude remains the conservative fallback when no runtime is declared.
- Claude, Codex, Grok, and Pi are peer runtimes for channel sessions,
  jobs, and eligible background partitions. Codex and Grok are
  auto-detected: install the CLI and log in (`codex login` / `grok login`).
  A failed probe is retried on the next message, so no restart is needed
  for message routing; setup-card runtime lists still come from the boot
  probe and need `duoduo daemon restart` to pick up a new install. Pi ships
  inside duoduo — nothing to install, always reported available, but every
  pi session needs a model pointer (`provider/modelId`) from job
  frontmatter, `/model`, or partition frontmatter.
- Runtime selection can happen per actor, per channel kind, or globally with
  `ALADUO_DEFAULT_RUNTIME` (`claude`, `codex`, `grok`, or `pi`).
- A runtime value duoduo does not know is refused, never replaced by another
  runtime: in `ALADUO_DEFAULT_RUNTIME` the daemon does not boot; in a channel
  descriptor the turns whose runtime that layer selects are refused (a valid
  instance value overrides an unknown kind value); a job fails; a partition
  is skipped — each with a sentence naming the value and the valid ones.
  `void` is a channel value meant for plugins such as tether whose sessions
  never run a model; it is refused as the default, on a job, and on a partition.
- Verify `codex` is installed and authenticated before routing work to it.
  For `grok`, duoduo only checks the binary — verify the login yourself
  before routing work to it. Explicit codex or grok that cannot be served
  is a hard failure — the turn is refused with the reason, never run on
  Claude. Pi is the same posture: a pi session with no resolvable model
  fails with the fix named in the reply, never a silent Claude run.

### Switching a session's runtime

A session is bound to the runtime that owns its conversation id; runtime
histories are not interchangeable. Changing only the `runtime` value —
instance or kind descriptor, `ALADUO_DEFAULT_RUNTIME`, job frontmatter — does
not move an existing session. Its next turn is refused ("Request was not
executed"), naming the bound runtime, the session id, and the configured one.

- **The only sanctioned switch**: `/clear` the channel session first, then
  change the runtime. A `/model` override set under the old runtime is dropped
  on the new one; a same-runtime `/model` override survives `/clear`, and so
  does `/effort`.
- **Refused at write time**: `duoduo session config <target> set runtime=<rt>`
  on an instance, and a channel re-spawn (e.g. a setup card) that changes the
  runtime, refuse while any session of that channel is bound elsewhere, and
  list those sessions — `/clear` each, then retry. Kind-scope, env, and job
  frontmatter changes are not checked at write time; affected sessions refuse
  at their next turn.
- **Backing out**: revert the runtime to the bound one and send the message
  again — the session resumes normally.
- **Keep prior work**: before switching for real, the old session's history
  stays on disk under the id the refusal names. Have a subagent locate and
  summarize it, then `/clear`.
- **Jobs**: a stateful job whose runtime no longer matches fails the run
  (`job.fail`, owner woken, retried on the failure backoff) until the owner
  decides — revert the runtime, or start the work on a new job. Stateless
  jobs are unaffected.

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

The mechanical (no-LLM) half of memory maintenance is the
`duoduo memory` CLI: lint checks that post `.pending` signals into
partition inboxes, plus the manual orphan `reclaim` lifecycle. Read
[references/memory-cli.md](references/memory-cli.md) when an operator
or a partition needs it directly.

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

## Slash Commands (`/compact`, `/model`, `/effort`)

`/compact` shrinks the context window in place. It works on every
runtime and flows through the normal channel message pipeline
(spine → mailbox → drain), so the user gets a regular text reply
when the command finishes.

Read [references/slash-commands.md](references/slash-commands.md)
for the runtime semantics, troubleshooting when a command appears
not to work, and what to tell a confused user.

`/model` switches the model for a session at runtime without a restart.
Read [references/model-switching.md](references/model-switching.md)
for syntax, Claude vs Codex timing differences, and how to recover
from an invalid model id. On Pi, `/model` is store-only and the
session's worker is rebuilt with the new model on the next message —
see [references/pi-runtime.md](references/pi-runtime.md).

When the user wants a model for **many** sessions rather than one — every
session of a channel kind, or the whole host — that is a model default
(`claude.model` / `codex.model` / `pi.model` / `grok.model`, 0.8.1+), set with
`duoduo session config` at the global, kind, or instance layer. Read
[references/model-defaults.md](references/model-defaults.md) for the layers,
what outranks what, and the two things `/model` now reports: the config layer a
session inherits from, and the model that actually served its last turn. Reach
for that file whenever a user says a model "will not stick" or "went back to
the old one" — the two lines are the diagnosis.

For hosts running third-party models, **model profiles** teach duoduo each
model's real context window, its endpoint + credentials (per-model routing),
and subagent tier aliases (Claude runtime only — codex has no profile
namespace). Read
[references/model-context-profiles.md](references/model-context-profiles.md)
**before answering any profile question** — it is written as guided playbooks
(add a model / route to an endpoint / remap tiers / troubleshoot / probe an
endpoint) with plain-language phrasings to relay, plus the
mechanism facts at the bottom for your own verification. Non-negotiables it
enforces: secret custody (you may receive a key the human hands you — in chat,
env, or file — but the raw value must never appear in anything you emit; take it
into the profile store immediately and confirm masked), evidence before any
number, confirm before writes that cost a rebuild.

`/effort` sets how hard the model reasons for a session
(`low | medium | high | xhigh | max`) — an independent axis from `/model`.
It applies live on Claude (a Claude model without `max` support runs `max`
as `high`), and from the next message on Codex and Pi (on
Pi the levels map onto pi's native thinking levels). Invalid values are
rejected up front; on Grok the level must be one the model supports,
otherwise the change is rejected. See the `/effort`
section of [references/slash-commands.md](references/slash-commands.md).
Both knobs are also settable per session from the CLI (0.8.0+) via
`duoduo session model` / `duoduo session effort` — see
[references/session-cli.md](references/session-cli.md).

## Session Management (`duoduo session …`)

These subcommands manage sessions from the CLI (human, agent-via-Bash, or
external script — one entry point):

- `duoduo session list [--kind …] [--named] [--json]` — the live route table.
- `duoduo session alias <key> "<name>"` — give a session a human label, so it
  is legible in `list` and usable as a `notify` target. Unnamed sessions show
  `—` (they are NOT auto-labelled with their key).
- `duoduo session notify <target> -m "<msg>" [--force]` — reach a session by
  key OR alias now and deliver a source-tagged notification. Only
  `channel`/`job` targets are allowed; the subconscious/kernel plane is
  isolated and refused. A channel session nobody has read for an hour is
  refused with `no_consumer` (0.8.2+; the reply names sessions that do have a
  reader; `--force` overrides). A notification tagged `<room> · <device>`
  came from an ambient device with the `notify` scope (duoduo-ambient,
  `references/devices.md`); revoke the device there to stop them.
- `duoduo session wake <target> --in <duration> | --at <iso>` (new since
  v0.8.1) — schedule ONE future turn of that session, with the context read
  from stdin. Notify delivers now; wake delivers later. Same target rule as
  notify: `channel`/`job` only, the subconscious/kernel plane refused. Cancel
  it before it fires with `duoduo job archive <wake-id>`.
- `duoduo session model <target> [<id>|reset]` / `duoduo session effort
  <target> [<level>|reset]` (0.8.0+) — inspect or set a channel session's
  model / reasoning effort from the CLI, same knobs as in-chat `/model` and
  `/effort`, without entering the session's chat. Channel sessions only.
- `duoduo session archive <key>` — move (never delete) a session's artifacts.

When the user says "name this session X" / "把这个会话叫 X", or wants to wake
one session from another by name, this is the surface. Read
[references/session-cli.md](references/session-cli.md) for full usage, the
isolation boundary, output/`--json` discipline, and the refusal reasons.

## Job Lifecycle (`duoduo job …`, new since v0.8.1)

Scheduled jobs are inspected and ended from the CLI. The in-session tool
creates, lists and reads them; every verb that ends or re-times a job is a
shell command, so a human at a terminal, an agent going through Bash, and an
external script all reach for the same one.

- `duoduo job list [--json]` — active jobs with schedule, pending one-off fire,
  last run and last result. Pending wakes are listed here too, typed `wake`,
  whether a session scheduled one for itself or an operator scheduled it with
  `duoduo session wake`.
- `duoduo job read <id> [--json]` — one job's definition, mission, and last run
  including its error.
- `duoduo job archive <id>` — stop future scheduling. Nothing is deleted: the
  job's files move to `var/jobs/archive/` and its session is archived with it.
  A run already in progress runs to its end. This is also how a pending wake is
  cancelled.
- `duoduo job interrupt <id> -r "<reason>"` — request the end of the run in
  progress. `-r` is required, and the reason is what that job is told on its
  next run, so write what changed rather than "stop". How the run settles is
  the job's own lifecycle, not the command's: a one-shot that was never
  re-armed is archived and its owner is told it failed, any other job stays
  scheduled, and a run cut off before it had taken up its turn is preserved as
  if it never started. Do not read "interrupted" in the receipt as "that run is
  dead" — it means the request was accepted.
- `duoduo job reschedule <id> <when>` — one extra fire at `@in 30m` or an ISO
  timestamp with an explicit zone. The schedule class is never changed.

Two verbs, two meanings, and they are easy to swap by accident: `archive` stops
future runs and leaves the current one alone, `interrupt` ends the current run
and leaves the schedule alone. A wedged recurring job usually wants both.

State the reach of `interrupt` honestly when a user asks: the runtime is asked
to stop. A tool that ignores its abort signal is not killed, and work the run
detached into a background process is not reached at all.

## Spine Inspection (`duoduo spine …`, 0.8.0+)

The event log (Spine WAL) is read through the CLI, not by opening the JSONL
partitions — a single day can be 10-30MB with megabyte-long tool results, and
92% of raw lines are tool plumbing the reader does not need.

- `duoduo spine cat --date <yyyy-mm-dd> [--session <key>] [--type <t>]…
  [--kind external|all] [--from … --to …] [--after <id>] [--json]` — a compact
  transcript: human/agent text in full, tool calls collapsed to one line with
  `use=`/`res=` drill-down anchors, an honest multi-count header and an
  `END spine` footer (no footer = the read was truncated). `--date` defaults to
  today. All times are UTC and every range is `(from, to]`; `--from/--to` also
  accept absolute ISO instants with an offset (`2026-08-31T08:29+08:00`), and
  such a range may span several days. `--after <id>` resumes strictly after one
  event inside the same bounds, so the output is a suffix of the same read.
- `--kind external` is **turn-scoped, not a source filter**: it keeps events
  that came from outside plus the internal rows of the turn each kept
  `channel.message` opened. Job sessions do not expand. Default is `all`.
- `duoduo spine cat --interval '<date>[t1,t2]' …` — the machine-shaped bounded
  read (this is what the subconscious uses), one partition, same `(t1, t2]`
  edges. **Always quote the interval: zsh treats the brackets as a glob and
  fails before the CLI runs.**
- `duoduo spine cat … --sessions` — per-session summary (exact key, event
  count, first/last ts) for finding a session key on a busy day.
- `duoduo spine cat … --count-only` — sizes only, no body; check before
  pulling a large window into an agent's context.
- `duoduo spine show <event-id> [--date <yyyy-mm-dd>]` — one event, full JSON,
  nothing elided. Row ids are shortened for display; `show` accepts any unique
  prefix and lists candidates when ambiguous. The by-id index is a boot-compacted
  recency cache. An older bare id falls back to a full partition scan; `--date`
  only narrows that scan, and the WAL row is unchanged.
- A `cat` that would print a body with no narrowing filter refuses unless
  `--unfiltered` is passed — that is protection for agent context windows, not a
  permission. `--count-only` and `--sessions` print no body and are exempt, so
  sizing a whole day never needs the flag.
- `missing_partitions=` / `skipped_malformed=` in the header are disclosures,
  not errors: a day with no events writes no partition file, and a torn final
  line is a normal crash artifact.

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
