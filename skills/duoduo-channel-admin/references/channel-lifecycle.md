# Channel Lifecycle

Use this reference for install/start/stop/status/logs work.

## Feishu

Official package:

```bash
duoduo channel install @openduo/channel-feishu
```

For the simplest setup, get the official Feishu bot `App ID` and `App Secret`
from:

- [open.feishu.cn/page/openclaw?form=multiAgent](https://open.feishu.cn/page/openclaw?form=multiAgent)

Required host-mode credentials live in:

```bash
~/.config/duoduo/.env
```

The agent may write them on the user's behalf if the user pastes the values into
chat, but it should warn first that `FEISHU_APP_ID` and `FEISHU_APP_SECRET` are
sensitive credentials and that sharing them in chat has the usual exposure and
retention risks.

Typical keys:

- `FEISHU_APP_ID`
- `FEISHU_APP_SECRET`
- optionally `FEISHU_DOMAIN`

Lifecycle commands:

```bash
duoduo channel feishu start
duoduo channel feishu status
duoduo channel feishu stop
duoduo channel feishu logs
```

## ACP (Editor Integration)

Official package:

```bash
duoduo channel install @openduo/channel-acp
```

ACP (Agent Client Protocol) bridges editor integrations such as Zed and Cursor
to the duoduo daemon. Each ACP session maps 1:1 to a daemon session.

No credentials are required. Lifecycle commands:

```bash
duoduo channel acp start
duoduo channel acp status
duoduo channel acp stop
duoduo channel acp logs
```

## Generic Plugin Rule

`duoduo channel install` accepts:

- an npm package spec such as `@openduo/channel-feishu`
- a local `.tgz` tarball path

It does not treat a raw Git repository URL as an install target.

## WeChat Rule

For WeChat, first determine which of these is true:

1. A published prebuilt package such as `@openduo/channel-wechat` exists and
   contains duoduo-compatible channel plugin metadata. Install that package.
   Do not substitute `@openduo/channel-weixin` unless that package is actually
   present in npm.
2. A local `.tgz` tarball exists. Install the tarball.
3. Only source code exists. Package or publish it before trying to install it
   with duoduo.

Preference order for end users:

1. published npm package
2. local prebuilt tarball
3. source checkout + build

Only use source checkout + build in developer or unreleased-package scenarios.

After `duoduo channel wechat start`, check `duoduo channel wechat logs` for
`QRCODE_READY:<path>`.

Resolve the state dir for QR helpers in this order:

1. `WECHAT_STATE_DIR` from `~/.config/duoduo/.env`
2. the directory part of `QRCODE_READY:<path>` when logs already have it
3. the default `~/.aladuo/channel-wechat`

Only run `qrcode-terminal` when the current login attempt has emitted a fresh
`QRCODE_READY:<path>`. A leftover `qrcode.png` in the state dir may be stale
from an older run and is not enough to prove there is a pending QR to render.

Display rules for the QR image:

1. If the current client can show local images, render the local PNG directly.
2. In stdio or TTY flows, prefer the plugin QR subcommand instead of parsing
   timestamped logs: `duoduo-wechat qrcode-terminal --state-dir <dir>`.
3. If the bin is not on `PATH`, inspect
   `<runtime_dir>/plugins/channels/wechat/manifest.json`, read `packageRoot`,
   and run `node <packageRoot>/dist/plugin.js qrcode-terminal --state-dir <dir>`.
4. If there is no QR subcommand available, at least output the PNG path and the
   next step.
5. For remote channels such as Feishu, read the QR path from logs and send the
   image to the user.

## Verification

After any install or restart:

1. Run `duoduo channel list`.
2. Run `duoduo channel <type> status`.
3. If startup fails, read `duoduo channel <type> logs`.
