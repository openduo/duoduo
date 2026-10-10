---
name: duoduo-ambient
description: "Set up and run the ambient channel so the owner can talk to duoduo from the 多多随身 (DuoDuo Pocket) iPhone app and a FoloToy AI Passport with pocket firmware: install @openduo/channel-ambient, point it at a cerebellum the owner already has (wss URL and token, or a provider's Tailscale share link and onboarding text), create a pocket room, publish it to the owner's tailnet with tailscale serve, connect the app, pair the Passport, and operate it later (restart, upgrade, add a room, troubleshoot 401/superseded/host not allowed, draft a tailnet ACL). Use when the owner wants to use duoduo from the phone or the Passport, or asks about the ambient channel. Does not build or host the cerebellum, the app or the firmware; it points to their public repos. Triggers: 多多随身, 随身, Passport, 按住说话, 环境模式, ambient 频道, 小脑, cerebellum, 手机连多多, 用手机和多多说话, 配对 Passport, tailscale serve 多多, 多多小脑接入, 分享链接."
---

# Duoduo Ambient

The owner says "I want to talk to you from my phone" or "set up the Passport". You drive it from
start to finish: the ambient channel runs on this host, reaches the owner's cerebellum, serves one
pocket room to the owner's tailnet over HTTPS, and the owner's 多多随身 app and Passport talk to it.
The owner only supplies the cerebellum token on the host terminal, approves each change, and does
the taps on the phone and the Passport.

What exists before you start, and is not this skill's work:

| Piece                                                    | Where it comes from                                                                                                                                                                                                                                       |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A cerebellum the owner can reach: `wss://` URL and token | The owner runs one, or someone runs it for them. Self-hosting it and its model services: [openduo/ambient](https://github.com/openduo/ambient), `docs/requirements.md`, `docs/deploy.md`, `services/`                                                     |
| The 多多随身 app on the owner's iPhone                   | TestFlight beta: apply with the [sign-up form](https://docs.google.com/forms/d/e/1FAIpQLSfIUllzEsHU18l3q_K1SBo8FBx-GztPhzUKotWpp74mYAIH-A/viewform); the invitation arrives by email. Source: [openduo/pocket-ios](https://github.com/openduo/pocket-ios) |
| A FoloToy AI Passport with pocket firmware (optional)    | [openduo/pocket-passport](https://github.com/openduo/pocket-passport), `docs/pocket/README.md`                                                                                                                                                            |
| Tailscale on this host and an account for the phone      | The owner's own tailnet                                                                                                                                                                                                                                   |

## General policy

Follow these throughout. Each rule carries its reason.

1. **Tailnet only, never public.** The page and API are reached through `tailscale serve` (or an
   SSH tunnel for one machine), never `tailscale funnel` or any other public ingress. Reason: the
   channel has no login of its own; tailnet membership is its only access control, so a public
   address hands the room, its history and its microphone path to anyone.
2. **Never change something that already exists to make room**: another service's serve route,
   the tailnet policy, a firewall, another channel's room. Adding is allowed; moving, replacing or
   deleting is not. If the only way needs a change, stop and give the owner the options. Reason:
   those belong to work you cannot see.
3. **The token never passes through chat.** The owner writes `AMBIENT_CEREBELLUM_TOKEN` into
   `~/.config/duoduo/.env` on the host terminal (step 2). You check that it is set, never what it
   is, and never print, echo, log or paste it. Reason: every reply lands in duoduo's event log, and
   a leaked token lets anyone use the owner's cerebellum.
4. **Each change needs the owner's yes, one at a time**: each install, `.env` edit, room creation,
   start or restart, and `tailscale serve` change. Reads and checks need no approval. Reason: a
   restart severs every connected device, and a serve route changes who reaches this host.
5. **One channel per room, one phone per room.** Never start a second channel (on this host or
   another) for a room that is already served. Reason: a second link to the cerebellum for the same
   room takes it over, and the first channel stops for good (`superseded`).
6. **Prove it, hand it over, say what is proven.** A step is done when its check passed. Transport
   health is not acoustic acceptance: say which of the phone, voice-note and Passport checks the
   owner actually did. Reason: the owner decides on risk.

## Set it up, start to finish

### 0. Prerequisites

Ask or check, then stop at the first gap and point the owner to its row in the table above.

```bash
duoduo daemon status                       # the channel needs the running daemon
duoduo channel list                        # is ambient already installed?
tailscale status --self                    # this host on a tailnet; note <node>.<tailnet>.ts.net
tailscale serve status                     # what is already served (policy 2)
```

On macOS, `tailscale` is the app's CLI by full path if it is not on `PATH`. Ask the owner:

- "Do you have your cerebellum's `wss://` address and its token?" Only the URL may be said in chat.
- "Did someone who runs a cerebellum for you send a share link or an onboarding text?" If so, read
  [references/shared-cerebellum.md](references/shared-cerebellum.md) first: it covers accepting
  the shared node and getting the token without it passing through chat.
- "Is 多多随身 installed on your iPhone, and is your Passport flashed with pocket firmware?"
  If the app is not installed, give the owner the [TestFlight sign-up form](https://docs.google.com/forms/d/e/1FAIpQLSfIUllzEsHU18l3q_K1SBo8FBx-GztPhzUKotWpp74mYAIH-A/viewform) and continue
  with the host steps while the invitation is pending.
- "Which Tailscale account will the phone log in with?" It must be the same tailnet as this host.

If the channel is installed and a room is served already, this is not a setup: go to
[references/operations.md](references/operations.md).

### 1. Install the channel

```bash
duoduo channel install @openduo/channel-ambient
duoduo channel list                        # shows ambient and its version
```

The install also copies the kind config (`config/ambient.md`) into the daemon's kernel config
directory when none is there. Do not edit its `bridge:` block: every key is required and the
shipped values carry their basis. Verbs, endpoints and logs: [references/channel.md](references/channel.md).

### 2. The channel's environment

The duoduo CLI loads `~/.config/duoduo/.env` when it starts a channel, filling only keys not
already set in its environment, and passes the plugin only the keys on its allowlist. Write the
keys there, not under the plugin directory.

1. Pick a free loopback port: `lsof -nP -iTCP:<port> -sTCP:LISTEN` prints nothing. There is no
   default on purpose.
2. With the owner's yes, add `AMBIENT_HTTP_PORT=<port>` and `AMBIENT_CEREBELLUM_URL=wss://…`
   (the URL the owner gave).
3. The owner adds the token on the host terminal. Send them this, verbatim:

   ```bash
   bash -c 'read -rsp "Cerebellum token: " T; echo; printf "AMBIENT_CEREBELLUM_TOKEN=%s\n" "$T" >> ~/.config/duoduo/.env'
   chmod 600 ~/.config/duoduo/.env
   ```

4. Check without reading the value:

   ```bash
   grep -cE '^AMBIENT_(HTTP_PORT|CEREBELLUM_URL)=.' ~/.config/duoduo/.env    # 2
   grep -qE '^AMBIENT_CEREBELLUM_TOKEN=.' ~/.config/duoduo/.env && echo token set
   ```

   If a key appears twice, ask the owner which line stays. Full key table:
   [references/channel.md](references/channel.md), Environment.

### 3. Create the pocket room

Agree with the owner: a room id (`[A-Za-z0-9_-]+`, for example `my-phone`), the absolute workspace
the room's agent works in, and the runtime (`claude`, `codex`, `grok` or `pi`). None has a default.
One room per phone.

```bash
duoduo channel ambient room add <room_id> --workspace <absolute path> --runtime <runtime> \
  --name "<display name>" --pocket
duoduo channel ambient room list
```

`--pocket` writes the pocket room's instance prompt: short answers, conclusion first, no markdown,
because answers are read on the phone and the latest one on the Passport's 240×320 screen. The
verb refuses a room that exists.

Every published channel (0.1.0 and later) has the verb. If `room` is an unknown verb (a channel
installed from an older source build), use the fallback script, with the same arguments and the
same approval:

```bash
<this skill>/scripts/create-room.sh <room_id> <absolute path> <runtime> --pocket
```

It calls the daemon's `channel.spawn` over its Unix socket, refuses an existing room, and writes the
pocket note into the room's `descriptor.md` when that body is empty. The read-only TCP port
(`127.0.0.1:20233`) refuses `channel.spawn`; do not try it. Without the verb there is no
`--name`; the page shows the room id.

### 4. Publish to the tailnet

The channel binds `127.0.0.1` only and its host gate admits loopback and private LAN addresses,
not tailnet `100.64.0.0/10` addresses or `*.ts.net` names. So `tailscale serve` carries HTTPS to
loopback, and the channel is told the name.

1. Read `tailscale serve status`. If `:443` on this node is free, with the owner's yes:

   ```bash
   tailscale serve --bg --https=443 http://127.0.0.1:<port>
   tailscale serve status                 # the new entry, every earlier entry unchanged
   ```

   If `:443` already serves something else, do not touch it. Give the owner the options in
   [references/operations.md](references/operations.md), Serve port taken.
   If `serve` asks for a consent URL (HTTPS certificates off for the tailnet), hand it to the
   owner as one message and wait for "done".

2. With the owner's yes, add to `~/.config/duoduo/.env`:

   ```
   AMBIENT_HTTP_HOSTS=<node>.<tailnet>.ts.net
   AMBIENT_HTTP_ORIGINS=https://<node>.<tailnet>.ts.net
   ```

### 5. Start and accept the host side

With the owner's yes: `duoduo channel ambient start` (or `stop`, then `start`, if it was running).

```bash
duoduo channel ambient status
curl -s http://127.0.0.1:<port>/healthz                       # {"ok":true,"rooms":<n>}
curl -s "http://127.0.0.1:<port>/api/state?room=<room_id>"
```

Pass: `daemon_ok` and `cerebellum_ok` are `true`, `config_issues` is empty. Then from another
tailnet device (not this host): `curl -s https://<node>.<tailnet>.ts.net/healthz` answers the
same JSON. A `403 {"error":"host not allowed"}` means step 4.2 is missing or the channel was not
restarted. Anything else: [references/channel.md](references/channel.md), Troubleshooting.

### 6. Connect the phone

Give the owner the values, then walk them through [references/pocket-app.md](references/pocket-app.md):

| App field (zh / en)         | Value                          |
| --------------------------- | ------------------------------ |
| 频道主机 / Channel Host     | `<node>.<tailnet>.ts.net`      |
| 端口 · HTTPS / Port · HTTPS | `443`, HTTPS on (the defaults) |
| 房间名 / Room name          | `<room_id>`                    |

The app logs in to Tailscale itself (it appears as node `duoduo-pocket`), then 检查连接 / Check
Connection runs Tailscale → `/healthz` → `/api/state` and must pass all three.

Acceptance, done by the owner and confirmed to you:

1. Type a message in the app; an answer from 多多 arrives.
2. Hold to talk (按住说话 / Hold to Talk), say a sentence, release; the transcript appears and an
   answer follows.
3. Optional: turn on ambient mode (the waveform button, top right); answers are spoken only while
   it is on, otherwise shown.

Check each in the room: `curl -s "http://127.0.0.1:<port>/api/state?room=<room_id>"` shows
`ws_clients` at least 1 while the app is open.

### 7. Pair and use the Passport

Walk the owner through [references/passport.md](references/passport.md): 添加 Passport / Add
Passport in the app, numeric comparison confirmed with OK on the Passport and 配对 on the iPhone,
then hold OK, speak, release. Pass: the transcript shows on the Passport, then the answer, and
the same exchange appears in the app.

### 8. Write the handoff

Write a short note beside the channel's state (ask the owner where, for example
`~/.config/duoduo/ambient-HANDOFF.md`). No credentials in it. Record: purpose; channel version;
`AMBIENT_HTTP_PORT`; the cerebellum URL and which file holds the token (by path, never the value);
each room with workspace, runtime and display name; the serve entry (`https://<node>…` →
`http://127.0.0.1:<port>`) and every serve entry that existed before; the app's host and room;
whether a Passport is paired; which acceptance checks passed and which the owner did not do;
start, stop, verify and rollback ([references/operations.md](references/operations.md)); do not
touch: other serve routes, the tailnet policy, other channels.

## Later

- Restart, upgrade, add a room, stop, roll back, a serve port that is taken, moving the channel
  to another host: [references/operations.md](references/operations.md).
- Something does not work (401, superseded, host not allowed, a room that will not start):
  [references/channel.md](references/channel.md), Troubleshooting.
- The owner wants only the phone to reach the channel, not every tailnet device:
  [references/tailnet-acl.md](references/tailnet-acl.md). You draft; the owner applies.
- App screens, banners and what they mean: [references/pocket-app.md](references/pocket-app.md).
  Passport controls, settings, re-pairing: [references/passport.md](references/passport.md).
