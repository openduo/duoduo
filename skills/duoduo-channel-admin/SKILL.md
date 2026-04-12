---
name: duoduo-channel-admin
description: "Install, start, stop, inspect, and configure duoduo host-mode channels, especially Feishu and compatible npm or tarball channel plugins. Use when the user asks to run duoduo channel install/list/start/stop/status/logs, set Feishu credentials, package or install a WeChat channel plugin, configure stdio or Feishu prompts, adjust channel workspaces or streaming, or edit channel defaults in kind descriptors or instance descriptors. Also trigger for Chinese requests such as 帮我拉起 feishu 通道, 帮我拉起微信 channel, 配置 channel 提示词, 改 stdio 的 workspace, or 查看 channel 状态."
---

# Duoduo Channel Admin

This skill owns host-mode channel lifecycle and channel-facing configuration.

## Start With Channel Discovery

1. Confirm host mode with `duoduo daemon status`.
2. Read `duoduo daemon config` to resolve the actual `kernel_dir` and
   `runtime_dir`.
3. Inspect installed plugins with `duoduo channel list`.
4. When changing one specific channel instance, inspect the relevant
   `descriptor.md` before editing it.

Read [references/channel-lifecycle.md](references/channel-lifecycle.md) for the
actual install and lifecycle rules, and
[references/channel-config-model.md](references/channel-config-model.md) for the
kind-vs-instance config model.

## Install And Run Channels

### Feishu

Use the official install path:

```bash
duoduo channel install @openduo/channel-feishu
```

For the simplest credential setup, direct the user to get the official Feishu
bot `App ID` and `App Secret` from:

- [open.feishu.cn/page/openclaw?form=multiAgent](https://open.feishu.cn/page/openclaw?form=multiAgent)

Then ensure those host-mode credentials are present in `~/.config/duoduo/.env`
and start the plugin with:

```bash
duoduo channel feishu start
```

If the user wants the agent to do the setup for them, it is acceptable for them
to paste the `App ID` and `App Secret` directly into chat and ask the agent to
write `FEISHU_APP_ID` and `FEISHU_APP_SECRET` into `~/.config/duoduo/.env`.
Before doing that, explicitly remind them that these are sensitive credentials
and that sharing them in chat carries the normal leakage and retention risks.

Use `status`, `stop`, and `logs` for lifecycle operations.

### ACP (Editor Integration)

Install the official ACP bridge for editor integrations (Zed, Cursor, etc.):

```bash
duoduo channel install @openduo/channel-acp
duoduo channel acp start
```

No credentials are required. Each ACP session maps 1:1 to a daemon session.

### WeChat And Other Third-Party Channels

- Duoduo's installer accepts npm package specs or `.tgz` tarballs.
- Prefer prebuilt published packages first. For WeChat, prefer:
  `duoduo channel install @openduo/channel-wechat`
- Do not claim that `duoduo channel install https://github.com/...` works unless
  the runtime actually supports it.
- Only use source checkout + local build when one of these is true:
  the package is not published yet, the user explicitly wants a dev build, or
  the user only has a local unreleased tarball flow.
- For normal user setup, do not ask the user to clone the repo or run a build
  if a published prebuilt package already exists.
- After `duoduo channel wechat start`, read `duoduo channel wechat logs` for
  `QRCODE_READY:<path>`.
- If the client can render local images, show the local PNG directly.
- Resolve the WeChat state dir before using the QR subcommand. Prefer
  `WECHAT_STATE_DIR` from `~/.config/duoduo/.env`; otherwise use the default
  `~/.aladuo/channel-wechat`. If logs already contain `QRCODE_READY:<path>`,
  the directory name of that PNG is also the correct state dir.
- In stdio or TTY flows, prefer the plugin QR subcommand instead of parsing
  multiline logs. Use `duoduo-wechat qrcode-terminal --state-dir <dir>` when
  the package bin is available.
- If `duoduo-wechat` is not on `PATH`, inspect the installed channel manifest
  to find `packageRoot`, then run
  `node <packageRoot>/dist/plugin.js qrcode-terminal --state-dir <dir>`. In
  default host-mode installs the manifest lives at
  `<runtime_dir>/plugins/channels/wechat/manifest.json`.
- If the QR subcommand is not available, output the PNG path and the next step.
- For remote channels such as Feishu, read the QR path from logs and send the
  image to the user.

## Configure Channel Behavior

Use kind descriptors for defaults that should apply to every channel of a kind.
Use instance descriptors for one specific channel only.

- Kind descriptor:
  `kernel_dir/config/<kind>.md`
- Instance descriptor:
  `runtime_dir/var/channels/<channel_id>/descriptor.md`

Typical editable keys:

- `new_session_workspace`
- `prompt_mode`
- `time_gap_minutes`
- `stream`
- `allowedTools`
- `disallowedTools`
- `additionalDirectories`

Use [scripts/patch_markdown_frontmatter.py](scripts/patch_markdown_frontmatter.py)
for frontmatter edits that should preserve comments and the Markdown body.
For prompt-body rewrites, use `replace-body` or apply a direct patch when that is
clearer.

## Prompt Editing Rules

- The Markdown body of `kernel/config/<kind>.md` is the kind prompt.
- The Markdown body of `descriptor.md` is the instance prompt.
- Instance frontmatter and prompt override kind defaults for that one channel.
- Preserve guidance comments in bootstrapped files whenever possible.

## Operating Rules

- Prefer the smallest scope that matches the request: kind-level for defaults,
  instance-level for a single room or session surface.
- After changing channel credentials in `~/.config/duoduo/.env`, restart the
  affected channel process.
- After installing a new plugin, verify with `duoduo channel list` and
  `duoduo channel <type> status`.
- If the channel still fails after credentials, install state, and runtime
  config look correct, treat it as a likely product or plugin issue and use the
  public issue flow from
  [../duoduo-admin/references/issue-reporting.md](../duoduo-admin/references/issue-reporting.md).
- If the request is really about telemetry, cadence, debug logs, or Codex,
  hand off to `duoduo-runtime-admin`.
