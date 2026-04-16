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
- optionally `FEISHU_GROUP_CONTEXT_REMINDER` — set to `true` to enable passive
  group-chat context capture. When enabled, the Feishu channel quietly records
  group messages that are not directed at the bot, then surfaces the
  "since last reply" window as an additional context reminder the next time the
  bot is woken in that group. Default is `false` (disabled). The capture lives
  entirely inside the Feishu channel process; restarting the channel drops any
  uncaptured window.

Lifecycle commands:

```bash
duoduo channel feishu start
duoduo channel feishu status
duoduo channel feishu stop
duoduo channel feishu logs
duoduo channel feishu doctor   # v0.5+ — see "Feishu dev-console setup" below
```

### Feishu dev-console setup — the three-layer gotcha

Before users can complete a setup card click, the Feishu developer console
must be configured in three independent layers. Missing any one is the
most common cause of client-side error **200340** on button click; when
the three layers are wrong, the channel never sees the callback event at
all (check `duoduo channel feishu logs` — zero `card.action.trigger`
frames means it's the console side). Handler-side problems (uncaught
exception or a handler slower than ~3s) can also surface as 200340; those
show up as events that DID arrive in the log along with an error. This
is invisible from the duoduo side (Feishu exposes no API to introspect
subscription or release state), so operators must verify it in the
console manually.

Open `https://open.feishu.cn/app/<your_app_id>/event-sub` and check all three:

1. **事件配置** tab → subscribe to `im.message.receive_v1` so inbound messages
   reach the channel.
2. **回调配置** tab → choose **使用长连接** as the subscription mode, then
   click **添加回调 → 卡片** and tick **卡片回传交互 (`card.action.trigger`)**.
   This tab is separate from **事件配置**; subscribing events is not
   enough.
3. **应用发布 → 版本管理 → 创建版本 → 企业可见 → 发布上线**. The dev-console
   state is a draft until the app version is released; until then the Feishu
   server still serves the pre-release subscription snapshot.

When in doubt, run `duoduo channel feishu doctor` — it reports credentials,
daemon reachability, and project discovery automatically, then prints the
three-layer checklist with the direct dev-console URL. Operators without
admin rights to release the app cannot complete layer 3 themselves and need
their Feishu workspace admin to do it.

### v0.5 setup card UX (`/setup` command)

From v0.5 onwards, every new Feishu conversation (p2p or group) goes through
an explicit setup card before the channel accepts normal messages. The card
offers two dropdowns: a **Project** list populated from directories under
`ALADUO_WORK_DIR` that contain a `CLAUDE.md`, and a **Runtime** choice
(`claude` or `codex`). Clicking **Start** binds the channel to that project
and runtime.

Two entry points trigger the card:

- **First inbound message** on an unconfigured channel. The channel intercepts
  the message (does NOT forward it to the daemon), posts the setup card, and
  prompts the user to resend their original message after Start.
- **`/setup` slash command** in any state. Users run `/setup` to re-bind a
  configured channel to a different project or runtime. On a successful
  Start the channel writes the new descriptor and refreshes its own
  active-session cache. What happens next depends on what changed:
  - **Project (cwd) changed**: the cached `session_key` hashes the new
    cwd, so the next inbound message lands in a fresh session that
    reads the new descriptor. Immediate effect.
  - **Runtime changed but project unchanged**: the session_key hash is
    the same as before (it is derived only from cwd), so the running
    session is preserved and continues on its old runtime. The new
    runtime takes effect only when the old session idles out and a
    new session is materialized. This is a v0.5 limitation; users are
    told in the post-Start hint text.
  The old session is not touched and ages out naturally — duoduo does
  not forcibly archive it.

`/setup` permission model in group chats:

- **p2p**: always permitted.
- **Configured, v0.5+ descriptor has `bound_by`**: only the original
  `bound_by` user may re-bind. `bound_by` is recorded by
  `channel.spawn` from the card-click operator's `open_id`.
- **Configured, pre-v0.5 descriptor without `bound_by`**: fall back to the
  existing `FEISHU_GROUP_CMD_USERS` env allowlist. This keeps pre-upgrade
  deployments working without a manual backfill.
- **Unconfigured group**: first user to send `/setup` may proceed; their
  `open_id` becomes `bound_by` on the descriptor that Start writes.

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

## Doctor subcommand (v0.5+)

Every channel plugin can optionally expose a `doctor` subcommand for
self-diagnosis:

```bash
duoduo channel <type> doctor
```

The kernel runs the plugin entry with `doctor` as the first extra argument
and inherits stdio so remediation text reaches the terminal directly. The
command refuses to run while the same channel is already running (stop it
first with `duoduo channel <type> stop`).

For `feishu` in particular, `doctor` reports credentials (bot identity via
`bot/v3/info`), daemon reachability (`system.runtime.info` RPC), project
discovery (non-empty `CLAUDE.md` scan under `ALADUO_WORK_DIR`), and prints
the three-layer dev-console checklist.

Exit code semantics:
- Exit 0 means **only** the automated checks passed (credentials + daemon
  + project discovery). It does NOT certify that the Feishu dev-console
  layers are OK — those cannot be introspected via API. Operators still
  need to eyeball the checklist even on a green run.
- Exit non-zero means an automated check failed; the failing line in the
  output explains which.

Recovery flow for 200340 once doctor has pointed at the fix:
1. Edit the Feishu developer console (events tab / callback tab /
   app-version release as doctor's checklist indicates).
2. Re-click the Start button on the existing setup card, or send `/setup`
   again — no need to restart the channel process. The running WS client
   picks up the next event once the console change is live.
3. Restart the channel only when you need to run `doctor` itself (doctor
   refuses to start while the channel is running because it shares
   credentials and would race the live WS subscription).

Channels that predate doctor support will fail the subcommand with a plugin
error — that is the signal to upgrade the plugin.
