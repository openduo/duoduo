# Running the ambient channel

Day-to-day work after setup. Read it from `SKILL.md` "Later", or when the owner asks to restart,
upgrade, add a room, stop, or move the channel. Each change needs the owner's yes
(`SKILL.md` policy 4); reads do not.

Contents:

- Check
- Restart
- Upgrade
- Add a room
- Change the cerebellum or its token
- Serve port taken
- Stop and roll back
- Move to another host

## Check

```bash
duoduo channel ambient status
curl -s http://127.0.0.1:<port>/healthz
curl -s "http://127.0.0.1:<port>/api/state?room=<room_id>"     # daemon_ok, cerebellum_ok, config_issues
tailscale serve status                                         # the entry to 127.0.0.1:<port> is there
```

## Restart

`duoduo channel ambient stop`, then `duoduo channel ambient start`. A restart drops every
connected device; the app reconnects by itself, and ambient mode must be turned on again if it was
on. After it: the Check above, and a `cerebellum_halt` from before the restart is cleared.

Restart after any `.env` change, a new room, or an upgrade.

## Upgrade

```bash
duoduo channel list                                   # current version
duoduo channel install @openduo/channel-ambient       # with the owner's yes
duoduo channel ambient stop && duoduo channel ambient start
```

- The install does not overwrite an existing kind config (`config/ambient.md`). If the release
  notes say the `bridge:` block gained a key, the channel refuses to start and names the key: copy
  it from the new package's `config/ambient.md` with the owner's yes.
- Upgrading from a channel without device tokens (0.2.x and older) locks every phone and browser
  out until paired. Straight after the restart, issue a link per device
  ([devices.md](devices.md), After an upgrade). An app older than device tokens must update first.
- If the cerebellum is run by someone else, ask first which wire version it serves. A channel
  newer or older than the cerebellum supports halts with `unsupportedProtocol`.

## Add a room

One room per phone, so a second phone gets a second room:

```bash
duoduo channel ambient room add <room_id> --workspace <absolute path> --runtime <runtime> \
  --name "<display name>" --pocket
```

Then restart, and pair the second phone to the new room (`device add <name> --room <new room_id>`,
[devices.md](devices.md)). Rooms on one channel share
its port and serve entry, and each room is its own session with its own history.

A room for a browser page or an e-ink tablet in a physical room (always listening, answers spoken)
is created without `--pocket`. Opening it: `https://<node>.<tailnet>.ts.net/?room=<room_id>`; the
microphone needs HTTPS or `127.0.0.1`.

Removing a room is deleting its directory, which deletes its history and notes. Do not do it; tell
the owner what it would delete and let them decide and do it.

## Change the cerebellum or its token

- New URL: with the owner's yes, replace the `AMBIENT_CEREBELLUM_URL` line, then restart.
- New token: the owner deletes the old `AMBIENT_CEREBELLUM_TOKEN` line and runs the `read -rs`
  command of `SKILL.md` step 2 again. Check with the `grep -q` line, then restart.
- The owner moves from a hosted cerebellum to their own: same two keys; nothing else on this host
  changes. Speaker numbers and usage records stay on the old cerebellum's host.

## Serve port taken

`tailscale serve status` shows `:443` already served to something else. Do not change that entry.
Options for the owner:

| Option                                                | Change                                                                                                                                               | Risk                                                         |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Another HTTPS port on the same node, for example 8443 | `tailscale serve --bg --https=8443 http://127.0.0.1:<port>`; `AMBIENT_HTTP_ORIGINS=https://<node>.<tailnet>.ts.net:8443`; the app's port set to 8443 | Not measured with the app; a tailnet ACL must allow the port |
| The owner moves the other service themselves          | None by you                                                                                                                                          | It is their service                                          |
| Run the channel on another host that runs the daemon  | A separate setup                                                                                                                                     | More to maintain                                             |

Never serve the channel under a path of another site (`--set-path`): the page and API use
absolute paths and break.

## Stop and roll back

| Undo            | Command                                                                                                                |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| The channel     | `duoduo channel ambient stop`                                                                                          |
| The serve entry | `tailscale serve --https=443 off` (only the entry you added; read `serve status` before and after)                     |
| The `.env` keys | Remove the `AMBIENT_*` lines with the owner's yes; the owner removes the token line                                    |
| A device        | `duoduo channel ambient device revoke <name>`; it must be paired again to come back                                    |
| The app         | Settings › Tailscale › 退出登录 / Log Out on the phone; remove `duoduo-pocket` in the admin console if the owner wants |
| The Passport    | Forget it in iOS Settings › Bluetooth; re-pair on the device                                                           |

Stopping keeps every room, its history and notes. The room's history is in
`<runtime_dir>/var/channels/ambient-<room_id>/`; back it up before moving anything.

## Move to another host

The channel runs beside a daemon; the rooms belong to that daemon. A move is a new setup on the
new host from `SKILL.md` step 1, with new rooms, and every device paired again (tokens belong to
one channel's device file). Carrying a
room's history and session across daemons is not covered by this skill: tell the owner, and back
up the old room directories before anything. Stop the old channel before starting the new one if
they share a room id on the same cerebellum: the second link for a room halts the first
(`superseded`).
