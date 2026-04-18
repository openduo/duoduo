# WeChat channel operations

Guidance for `@openduo/channel-wechat`. Load when the user's request
involves WeChat (微信) — installation, starting, QR-code login, or
packaging a local dev build.

## Install

Prefer the published package over cloning:

```bash
duoduo channel install @openduo/channel-wechat
```

The official npm name is `@openduo/channel-wechat`. Do NOT rewrite to
`@openduo/channel-weixin` unless the registry actually contains that
package. Do NOT claim `duoduo channel install <github-url>` works
unless the runtime version actually supports it.

Source checkout + local build is only appropriate when: the package
is not published yet, the user explicitly wants a dev build, or the
user has a local unreleased tarball flow.

## Start and QR login

```bash
duoduo channel wechat start
duoduo channel wechat logs
```

After start, the logs will contain a line like:

```
QRCODE_READY:/Users/antmanler/.aladuo/channel-wechat/qrcode.png
```

Scan that PNG with WeChat to authenticate. Options to surface the QR:

- If the client can render local images, show the PNG directly.
- In stdio / TTY, prefer the plugin subcommand:
  `duoduo-wechat qrcode-terminal --state-dir <dir>`.
- If `duoduo-wechat` is not on `PATH`, inspect the channel manifest
  at `<runtime_dir>/plugins/channels/wechat/manifest.json` for
  `packageRoot`, then run:
  `node <packageRoot>/dist/plugin.js qrcode-terminal --state-dir <dir>`.
- For remote channels (e.g. Feishu forwarding), send the PNG as an
  image message.
- Fall back to printing the PNG path + next step if no subcommand works.

## Resolving the state dir

A stale `qrcode.png` on disk is NOT enough — only use
`qrcode-terminal` when the current `start` / `logs` output contains a
fresh `QRCODE_READY:<path>`.

State-dir resolution order:

1. `WECHAT_STATE_DIR` from `~/.config/duoduo/.env` (when set)
2. The directory of the latest `QRCODE_READY:<path>` log line
3. Default `~/.aladuo/channel-wechat`
