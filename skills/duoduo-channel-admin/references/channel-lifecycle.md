# Channel Lifecycle

Use this reference for install/start/stop/status/logs work.

## Feishu

Official package:

```bash
duoduo channel install @openduo/channel-feishu
```

Required host-mode credentials live in:

```bash
~/.config/duoduo/.env
```

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

1. A published package such as `@openduo/channel-wechat` exists and contains
   duoduo-compatible channel plugin metadata. Install that package.
2. A local `.tgz` tarball exists. Install the tarball.
3. Only source code exists. Package or publish it before trying to install it
   with duoduo.

## Verification

After any install or restart:

1. Run `duoduo channel list`.
2. Run `duoduo channel <type> status`.
3. If startup fails, read `duoduo channel <type> logs`.
