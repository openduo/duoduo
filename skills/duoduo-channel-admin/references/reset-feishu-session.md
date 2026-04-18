# Reset a Feishu channel's session state

Use this when a chat has accumulated stale state and you want the next
`/setup` to behave as if the channel had never been bound. Common triggers:

- An experiment left behind sessions under the wrong runtime or workspace.
- A previous owner bound the channel with `bound_by`; the new owner wants a
  clean slate.
- A channel is bound to a workspace that no longer exists on disk.

The Feishu plugin can run on a DIFFERENT host from the daemon — this is a
supported deployment (plugin host talks to daemon over WebSocket JSON-RPC).
State is therefore split across two locations. Both must be reset and the
plugin MUST be restarted, otherwise the plugin keeps an in-memory map of
the old `session_key` → chat binding even after the on-disk state is gone.

## Where state lives

| Host              | Path                                         | What it holds                            |
| ----------------- | -------------------------------------------- | ---------------------------------------- |
| Daemon host       | `~/.aladuo/var/sessions/<hash>/`             | One session dir per session_key          |
| Daemon host       | `~/.aladuo/var/channels/<channel_id>/`       | Channel descriptor (workspace + runtime) |
| Feishu plugin host| `~/.cache/feishu-channel/watched-sessions.json` | Plugin's WebSocket subscriptions      |

When daemon and plugin run on the same host (the common case), both paths
sit under the same `$HOME` and the script's default `--role=auto` handles
them in one pass. For a split deployment run the script on each host with
the matching `--role`.

## The script

`scripts/reset-feishu-session.sh --channel-id <id>` does the following,
skipping any step whose target does not exist:

1. **daemon host**: grep `~/.aladuo/var/sessions/*/state.json` for
   `source_channel_id == <channel_id>`, move each matching dir to
   `sessions/.trash/<hash>.<ts>`.
2. **daemon host**: for each session hash moved in step 1, also move
   `~/.aladuo/var/ingress/<hash>/` to `ingress/.trash/<hash>.<ts>`.
   This is CRITICAL — the ingress directory stores raw JSON-RPC
   snapshots of every inbound message, and agents can read them via
   `ManageSession(show)` → the filesystem pointer it prints. Leaving
   ingress behind lets a fresh session quote historical messages
   verbatim, making the reset look broken.
3. **daemon host**: move `~/.aladuo/var/channels/<channel_id>/` to
   `channels/.trash/<channel_id>.<ts>` — unless `--keep-descriptor`.
4. **plugin host**: rewrite `~/.cache/feishu-channel/watched-sessions.json`,
   removing every entry whose `session_key` contains the chat OpenID.
5. **plugin host**: print a reminder to run `duoduo channel feishu stop && duoduo channel feishu start`.

Nothing is deleted outright. Everything goes to a `.trash` sibling with a
timestamp suffix so recovery is `mv` back.

### Flags

| Flag                    | Purpose                                                                 |
| ----------------------- | ----------------------------------------------------------------------- |
| `--channel-id <id>`     | Required. Shape: `feishu-oc_xxx`.                                        |
| `--role auto`           | Default. Detect which halves exist on this host and run those.          |
| `--role daemon`         | Only touch `~/.aladuo/`. Use on the daemon host of a split deployment.  |
| `--role plugin`         | Only touch `~/.cache/feishu-channel/`. Use on the plugin host.          |
| `--role both`           | Force both halves even if auto-detect would skip one.                   |
| `--aladuo-home PATH`    | Override the daemon-host root (default `$HOME/.aladuo`).                |
| `--plugin-cache PATH`   | Override the plugin cache root (default `$HOME/.cache/feishu-channel`). |
| `--keep-descriptor`     | Leave the channel descriptor alone. Next `/setup` is a re-bind, not a first-time welcome. |
| `--dry-run`             | Print the plan without modifying anything.                              |

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

Keep the descriptor so the operator does not have to re-pick project/runtime
but still wants a clean session:

```bash
bash reset-feishu-session.sh --channel-id feishu-oc_xxx --keep-descriptor
duoduo channel feishu stop && duoduo channel feishu start
```

## Finding the channel_id

The channel_id is `feishu-<chat_id>`. Get the chat_id from:

- The setup card request URL / daemon logs
  (`[card-action] card.action.trigger received`).
- The plugin log entry `[bot] handleFeishuMessage entry chatId=…`.
- The existing `~/.aladuo/var/channels/` listing on the daemon host.

## Why the restart is non-negotiable

`watched-sessions.json` is read at plugin startup. The plugin caches the
list in memory and writes it back on each subscribe/unsubscribe. Editing
the file while the plugin is running does NOT detach the old subscription —
the in-memory map still maps the chat to the old session_key. Only a
restart forces the plugin to reload the pruned list.

## What NOT to reset this way

- Active sessions currently being served by the runner. The script does not
  check for attach state; if the daemon is mid-turn on a target session,
  moving its dir out from under the runner will surface as a mailbox read
  error. Stop the daemon (or at least confirm no drain is in flight) before
  resetting sessions that were active in the last few seconds.
- Sessions belonging to other channel kinds (stdio, ACP, WeChat). The grep
  filter is scoped to one feishu channel_id; other kinds have different
  `source_channel_id` shapes and are not touched.
- Jobs. Job sessions persist independently under `var/jobs/`; this script
  does not prune job state.
