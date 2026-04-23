# Reset a Feishu channel's session state

Use this when a chat has accumulated stale state and you want the next
`/setup` to behave as if the channel had never been bound. Common triggers:

- An experiment left behind sessions under the wrong runtime or workspace.
- A previous owner bound the channel with `bound_by`; the new owner wants a
  clean slate.
- A channel is bound to a workspace that no longer exists on disk.

Since duoduo 0.5.0 the daemon exposes a single RPC — `session.archive` —
and a matching CLI `duoduo session archive <session_key>`. The CLI
archives the session dir, ingress snapshots, outbox records, and the
channel descriptor in **one atomic call**. "Archive" literally: nothing
is deleted, everything moves to a `<name>-archive/` sibling so recovery
is a `mv` back.

The script in this skill is a thin orchestrator:

1. On the daemon host, scan `state.json` files to find every session_key
   that points at the target channel, then invoke the CLI once per key.
2. On the plugin host, prune `watched-sessions.json` so the plugin stops
   re-subscribing to the old session_key, then print a restart reminder.

## Where state lives

| Host              | Path                                         | What it holds                            | Owner                     |
| ----------------- | -------------------------------------------- | ---------------------------------------- | ------------------------- |
| Daemon host       | `~/.aladuo/var/sessions/<hash>/`             | Session state.json, mailbox, inbox       | `duoduo session archive`  |
| Daemon host       | `~/.aladuo/var/ingress/<hash>/`              | Raw inbound message snapshots            | `duoduo session archive`  |
| Daemon host       | `~/.aladuo/var/outbox/<kind>/*.json`         | Outbound records (filtered by session_key)| `duoduo session archive`  |
| Daemon host       | `~/.aladuo/var/outbox/replay/*.jsonl`        | Reply replay log (one file per session_key)| `duoduo session archive`|
| Daemon host       | `~/.aladuo/var/channels/<channel_id>/`       | Channel descriptor (workspace + runtime) | `duoduo session archive`  |
| Feishu plugin host| `~/.cache/feishu-channel/watched-sessions.json` | Plugin's WebSocket subscriptions      | this script (file edit)   |

When daemon and plugin run on the same host (the common case), the
script's default `--role=auto` handles both. For a split deployment run
the script on each host with the matching `--role`.

## The script

`scripts/reset-feishu-session.sh --channel-id <id>` does the following,
skipping any step whose target does not exist:

1. **daemon host**: grep `~/.aladuo/var/sessions/*/state.json` for
   `source_channel_id == <channel_id>`. For each match, extract the
   `session_key` and call `duoduo session archive <key>`. The daemon
   archives every durable artifact in one atomic step; the in-memory
   `SessionIndex` observer fires so the dashboard stops showing the
   session immediately.
2. **plugin host**: rewrite `~/.cache/feishu-channel/watched-sessions.json`,
   removing every entry whose `session_key` contains the chat OpenID.
3. **plugin host**: print a reminder to run `duoduo channel feishu stop && duoduo channel feishu start`.

### Flags

| Flag                    | Purpose                                                                 |
| ----------------------- | ----------------------------------------------------------------------- |
| `--channel-id <id>`     | Required. Shape: `feishu-oc_xxx`.                                        |
| `--role auto`           | Default. Detect which halves exist on this host and run those.          |
| `--role daemon`         | Only touch the daemon via `duoduo session archive`.                     |
| `--role plugin`         | Only touch `~/.cache/feishu-channel/`.                                  |
| `--role both`           | Force both halves even if auto-detect would skip one.                   |
| `--aladuo-home PATH`    | Override the daemon-host root (default `$HOME/.aladuo`).                |
| `--plugin-cache PATH`   | Override the plugin cache root (default `$HOME/.cache/feishu-channel`). |
| `--duoduo-bin PATH`     | Absolute path to the `duoduo` CLI. Required when the binary is not on PATH (e.g. under the duoduo-manager install at `~/.duoduo-manager/bin/duoduo`). |
| `--keep-descriptor`     | Legacy; currently a no-op (prints a warning). `session.archive` always archives the channel descriptor alongside the session. If you need a different behavior, file an issue. |
| `--dry-run`             | Print the plan without touching the daemon or filesystem.               |

### Typical invocations

Single host (daemon + plugin together):

```bash
bash reset-feishu-session.sh --channel-id feishu-oc_5713a942f1e8e60d34b0ca644e3478b1
duoduo channel feishu stop && duoduo channel feishu start
```

Split deployment:

```bash
# on the daemon host
bash reset-feishu-session.sh --channel-id feishu-oc_5713a942f1e8e60d34b0ca644e3478b1 --role daemon

# on the feishu plugin host
bash reset-feishu-session.sh --channel-id feishu-oc_5713a942f1e8e60d34b0ca644e3478b1 --role plugin
duoduo channel feishu stop && duoduo channel feishu start
```

duoduo-manager install (no `duoduo` on PATH):

```bash
bash reset-feishu-session.sh --channel-id feishu-oc_xxx \
  --duoduo-bin ~/.duoduo-manager/bin/duoduo
```

## Finding the channel_id

The channel_id is `feishu-<chat_id>`. Get the chat_id from:

- The setup card request URL / daemon logs
  (`[card-action] card.action.trigger received`).
- The plugin log entry `[bot] handleFeishuMessage entry chatId=…`.
- The existing `~/.aladuo/var/channels/` listing on the daemon host.

## Recovery — how to undo

`session.archive` doesn't delete, it moves. Each target has an archive
sibling under `~/.aladuo/var/`:

| Live path                              | Archive path                                          |
| -------------------------------------- | ----------------------------------------------------- |
| `var/sessions/<hash>/`                 | `var/sessions-archive/<hash>/[.<ts>]`                 |
| `var/ingress/<hash>/`                  | `var/ingress-archive/<hash>/[.<ts>]`                  |
| `var/outbox/replay/<key>.jsonl`        | `var/outbox-archive/replay/<key>.<ts>.jsonl`          |
| `var/outbox/<kind>/<file>.json`        | `var/outbox-archive/<kind>/<file>.<ts>.json`          |
| `var/channels/<channel_id>/`           | `var/channels-archive/<channel_id>/[.<ts>]`           |

To recover: `mv` the archive back to its live location. (The daemon does
not re-scan archived dirs, so you may need to restart it for the restored
session to become visible on the dashboard.)

To **permanently** delete: after you're confident you won't need the
state, `rm -rf ~/.aladuo/var/*-archive/`. Nothing in the daemon lifecycle
cleans this up for you — by design.

## Why the restart is non-negotiable

`watched-sessions.json` is read at plugin startup. The plugin caches the
list in memory and writes it back on each subscribe/unsubscribe. Editing
the file while the plugin is running does NOT detach the old subscription —
the in-memory map still maps the chat to the old session_key. Only a
restart forces the plugin to reload the pruned list.

## What NOT to reset this way

- Active sessions currently being served by the runner. `duoduo session
  archive` refuses (exit code 2, reason=`active`) when the target has a
  live actor. Cancel the session first (e.g. via `/cancel` on the chat,
  or by stopping the feishu plugin so its actors drop) and retry.
- Sessions belonging to other channel kinds (stdio, ACP, WeChat). The
  grep filter is scoped to one feishu channel_id; other kinds have
  different `source_channel_id` shapes and are not touched. To archive
  those manually, run `duoduo session archive <session_key>` directly.
- Jobs. Job sessions persist independently under `var/jobs/`; archive
  them via `ManageJob(action=archive)` on the agent side instead.
