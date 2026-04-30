# Feishu channel operations

Comprehensive guidance for the `@openduo/channel-feishu` plugin. Load
this file when the user's request involves Feishu specifically — setup
card behavior, owner DM, `/setup` routing, 200340 errors, reset, or any
"the bot is acting weird" report about a Feishu channel.

## Contents

- Install and start
- Credentials
- v0.5 `/setup` routing matrix (owner DM / secondary DM / group)
- Main session contract (owner DM auto-spawn)
- `FEISHU_BOT_OWNER` + security hygiene
- 200340 error triage
- Reset a bound channel (when descriptor or session is stale)
- Stale first-time card (v0.5 guard)
- Accepted v0.5 limits (do NOT open as bugs)

## Install and start

```bash
duoduo channel install @openduo/channel-feishu
duoduo channel feishu start
```

Lifecycle: `status | stop | logs | start`. There is no `restart`
subcommand — use `stop && start` when a full cycle is needed.

## Credentials

Put `FEISHU_APP_ID` and `FEISHU_APP_SECRET` in `~/.config/duoduo/.env`.
For the simplest setup, get the official bot `App ID` and `App Secret`
from:
`https://open.feishu.cn/page/openclaw?form=multiAgent`.

The standard manual path is the Feishu developer console:
`https://open.feishu.cn/app`.

If the user pastes credentials directly in chat, warn them about
leakage risk once, then proceed to write them.

## v0.5 `/setup` routing matrix

The plugin routes `/setup` by (chatType, configured, descriptor shape,
operator identity). Read the matrix top-to-bottom; the first match wins.

| chatType | configured? | descriptor        | operator           | behavior                                                        |
| -------- | ----------- | ----------------- | ------------------ | --------------------------------------------------------------- |
| group    | no          | —                 | any allowlisted    | full setup card (no ⌂ workspace-root option)                    |
| group    | yes         | v0.5 (bound_by)   | bound_by           | compact rebind card (mention toggle only)                       |
| group    | yes         | v0.5 (bound_by)   | other              | plain-text refusal                                              |
| group    | yes         | pre-v0.5 (no bound_by) | allowlisted     | compact rebind card                                             |
| group    | yes         | pre-v0.5          | not allowlisted    | plain-text refusal                                              |
| p2p      | no          | —                 | owner (or zero-config) | auto-spawn to defaultWorkDir (main session; see below)       |
| p2p      | no          | —                 | non-owner          | setup card (no ⌂)                                              |
| p2p      | yes         | v0.5 bound_by==owner | owner           | plain-text refusal — "main session is locked"                   |
| p2p      | yes         | v0.5 bound_by≠owner | owner            | setup card (no ⌂) — descriptor drifted, let owner reassign      |
| p2p      | yes         | v0.5 bound_by     | non-owner          | setup card (no ⌂) — secondary DM flow                           |
| p2p      | yes         | pre-v0.5 (no bound_by) | any            | setup card (no ⌂) — legacy compatibility                        |

The **⌂** ("workspace root") dropdown entry is reserved for the
owner's main DM auto-spawn only. Every other render hides it. Granting
guests access to the root workspace would leak the whole project tree.

## Main session contract (owner DM)

The bot owner's DM is the **zero-prerequisite control surface**:

- First message on an unconfigured owner DM: plugin auto-spawns the
  channel to `defaultWorkDir` (daemon-handshake resolved) with the
  kind's default runtime (`kernel/config/feishu.md → runtime`, fallback
  `claude`). No card, no dropped message. The first message flows
  through ingress as normal.
- Owner is resolved from `cfg.botOwnerOpenId`:
  `FEISHU_BOT_OWNER` env → fallback `FEISHU_ALLOW_FROM[0]` → undefined.
- When undefined (zero-config), ANY first DM sender triggers auto-spawn
  but `bound_by` is NOT persisted — see "Security hygiene" below.

After auto-spawn, `/setup` on the owner DM is refused. The DM is
locked to `defaultWorkDir` so the operator always has a working
control channel even if other bots/config break. To relocate the
main session, run the reset script.

## Security hygiene

v0.5 auto-spawn on owner DM changes the implicit trust boundary.
Zero-config defaults are meant for bootstrap only.

Production `~/.config/duoduo/.env` should have:

```bash
FEISHU_BOT_OWNER=ou_yourOpenId       # explicit owner — locks main session
FEISHU_ALLOW_FROM=ou_you,ou_friend,… # additional DMs allowed as secondary
FEISHU_DM_POLICY=allowlist           # refuse DMs from users not in ALLOW_FROM
FEISHU_GROUP_POLICY=allowlist        # same for groups (see FEISHU_ALLOW_GROUPS)
FEISHU_GROUP_CMD_USERS=ou_you,…      # lets pre-v0.5 groups keep /setup access
```

When the user reports "strangers can DM my bot", check `dmPolicy`
first. When the user reports "/setup does nothing on my bot's DM",
check whether their open_id matches `FEISHU_BOT_OWNER` (the refusal
message says "main session is locked", which is the intended
behavior).

## 200340 error triage

If `card.action.trigger` clicks show Feishu error **200340**, run:

```bash
duoduo channel feishu doctor
```

The doctor subcommand prints the three-layer remediation checklist
(developer console subscription / app release / encryption). It must
be run while the plugin is **stopped** — `doctor` refuses to start on
a live process.

If `doctor` reports all three layers healthy, the error is likely
handler-side (crash or response exceeding Feishu's ~3s budget): grep
`duoduo channel feishu logs` for `card.action.trigger` frames and any
handler stack traces.

Recovering from 200340 usually does NOT require a full restart — once
the console is fixed, the running WebSocket client receives the next
event. Restart only if doctor itself must run.

## Reset a bound channel

When a Feishu chat has stale state (wrong project, abandoned test
session, ingress/outbox snapshots leaking historical messages), use
the reset script. See [reset-feishu-session.md](reset-feishu-session.md)
for the full walkthrough.

```bash
bash scripts/reset-feishu-session.sh --channel-id feishu-oc_xxx
duoduo channel feishu stop && duoduo channel feishu start
```

The restart is non-negotiable: the plugin caches subscription state
in memory (`watched-sessions.json`), so editing the file without a
restart does not detach the old subscription.

## Stale first-time card defense (v0.5)

The plugin re-calls `describeChannel` before every `channel.spawn`.
If the channel is now `configured: true` AND the card click carries
project or runtime fields (which the compact rebind card never
exposes), the click is refused with "already configured; send /setup
to re-bind". This prevents a stale first-time card (issued before
binding) from bypassing the compact-rebind rules.

When a user reports a "Setup failed: channel already configured"
toast, the fix is simple: have them send `/setup` to get the current
card, then click Start again.

## Group messages without `@bot` require an extra Feishu scope

Setting `FEISHU_REQUIRE_MENTION=false` (env) or unchecking the "Require
@" toggle in `/setup` (descriptor) tells the bot it should respond to
group messages even when not @-mentioned. **By itself this is a
no-op** unless the Feishu app has also been granted the sensitive
scope `im:message.group_msg` ("Read all messages in a group") and that
permission has been released into the published version of the app.

Symptoms when the scope is missing:

- Toggle is unchecked / env set to false
- Bot still only responds when explicitly @-mentioned
- Daemon log shows the message arriving but routed without a
  matching event
- No error — the Feishu webhook simply never delivers the
  un-mentioned group messages to the bot

Operator checklist when configuring `require_mention=false`:

1. Open the app on Feishu open platform → Permissions →
   `im:message.group_msg` ("Read all messages in a group" /
   "获取群组中所有消息")
2. Apply for the scope (sensitive, requires admin approval)
3. After approval, **publish a new version of the app** so the scope
   is actually live (granting alone is not enough on Feishu)
4. Restart the channel: `duoduo channel feishu stop && start`
5. Re-test with a non-@ message in the group

The setup card and rebind card render this hint inline below the
require_mention checker (v0.5+), and `duoduo channel feishu doctor`
includes it in the manual checklist. If a user toggles the box but
group messages still need @, this scope gap is the most likely cause.

## Accepted v0.5 limits

Two corner-case behaviors are known, evaluated, and deliberately not
fixed in v0.5. Recognize them and recover via the reset script
instead of treating them as new bugs.

### Limit 1 — first-time group binding race

If two operators in the same unconfigured group click their Start
buttons within milliseconds of each other, both preflight
`describeChannel` calls see `configured: false`, both spawns include
`bound_by`, daemon applies them serially, and the later writer wins.
The loser's click silently stubs over the already-bound descriptor
(though `bound_by` itself is protected by the
rebind-doesn't-write-bound_by guard).

Probability is low (coordinated clicks on same unconfigured group);
damage is contained (both operators are allowlisted). Recovery:
reset + intentional re-bind.

### Limit 2 — `FEISHU_BOT_OWNER` hygiene

The owner-DM refusal gate requires `cfg.botOwnerOpenId !== undefined`
(resolved once at plugin startup). If the operator accidentally
unsets `FEISHU_BOT_OWNER` in `.env` (typo, deletion) and restarts,
the main-session lock lifts — their own `/setup` falls through to
the secondary card and can reassign the DM.

This requires shell access, `.env` edit, and a restart — equivalent
to running the reset skill directly. Config-hygiene issue, not an
attack vector. Recovery: restore `.env` and restart.
