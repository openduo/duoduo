# ACP (Agent Client Protocol) bridge

Guidance for `@openduo/channel-acp`. Load when the user's request
involves editor integration (Zed, Cursor, or another ACP-speaking
editor).

## Install and start

```bash
duoduo channel install @openduo/channel-acp
duoduo channel acp start
```

No credentials required. Each ACP session maps 1:1 to a daemon
session — that's the main semantic difference from Feishu (where one
chat_id owns a session and switching projects rotates cwd).

Lifecycle: `status | stop | logs | start`.

## Session lifecycle (v0.5.2+)

The ACP bridge keeps the editor-side ACP session and the daemon-side
duoduo session in lockstep. When the editor opens a new ACP session,
the bridge spawns the corresponding daemon session immediately so the
editor's first prompt does not race the daemon's setup. When the
editor closes the session, the bridge releases the daemon session
cleanly.

What this means for users:

- A fresh editor session always sees the workspace it was opened
  against — no "first prompt landed in the wrong cwd" race.
- Closing the editor pane releases the daemon session; restarting the
  pane gets a new session with no residual context.
- `duoduo session list` will show one ACP session per active editor
  pane; the editor close event removes it.

If the editor and daemon disagree on workspace or the bridge appears
stuck, `duoduo channel acp restart` cycles the bridge without
restarting the daemon.

The design rationale is in `docs/30-runtime/channels/AcpChannelDesign.md`
in the source repo.

## What to tell a confused user

- ACP is a bridge, not a Feishu-style bot. The editor is the chat
  surface; duoduo runs behind it as the agent backend.
- ACP sessions don't have a setup card — the editor passes a
  workspace path directly. If the editor and duoduo disagree on the
  workspace, check the ACP client logs for the session init call.
