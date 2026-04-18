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

## What to tell a confused user

- ACP is a bridge, not a Feishu-style bot. The editor is the chat
  surface; duoduo runs behind it as the agent backend.
- ACP sessions don't have a setup card — the editor passes a
  workspace path directly. If the editor and duoduo disagree on the
  workspace, check the ACP client logs for the session init call.
