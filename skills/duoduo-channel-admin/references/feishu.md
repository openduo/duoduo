# Feishu channel operations

Comprehensive guidance for the `@openduo/channel-feishu` plugin. Load
this file when the user's request involves Feishu specifically — setup
card behavior, owner DM, `/setup` routing, 200340 errors, reset, or any
"the bot is acting weird" report about a Feishu channel.

## Contents

- Install and start
- Credentials
- v0.5 `/setup` routing matrix (owner DM / secondary DM / group)
- Owner DM contract (auto-spawn, automatic `main` claim)
- A second app, forwarding chats, `send` (separate references)
- `FEISHU_BOT_OWNER` + security hygiene
- 200340 error triage
- Reset a bound channel (when descriptor or session is stale)
- Inbound files with text
- Outbound media rendering (opus voice notes, image, files)
- Stale first-time card (v0.5 guard)
- Web search/fetch disabled by default (re-enable via descriptor)
- Accepted v0.5 limits (do NOT open as bugs)

## Install and start

```bash
duoduo channel install @openduo/channel-feishu
duoduo channel feishu start
```

Lifecycle: `status | stop | logs | start`. There is no `restart`
subcommand — use `stop && start` when a full cycle is needed.

A second Feishu or Lark app runs as a named instance of the same package
(`--instance <name>` on every verb): read
[feishu-second-app.md](feishu-second-app.md). To have a chat served by a
session that already exists — across apps or within one — read
[feishu-forward.md](feishu-forward.md).

## Credentials

Put `FEISHU_APP_ID` and `FEISHU_APP_SECRET` in `~/.config/duoduo/.env`.
For the simplest setup, get the official bot `App ID` and `App Secret`
from:
`https://open.feishu.cn/page/openclaw?form=multiAgent`.

The standard manual path is the Feishu developer console:
`https://open.feishu.cn/app`.

For Lark (the international version), create the app in the Lark
developer console, `https://open.larksuite.com/app`, use that app's own
`App ID` and `App Secret`, and add `FEISHU_DOMAIN=lark` to the same
`~/.config/duoduo/.env`. Without it the channel talks to the China
endpoints and a Lark app's credentials are refused. China Feishu needs
no `FEISHU_DOMAIN` line.

Prefer that the owner writes the secret into the file from their own
terminal (the handover in [feishu-second-app.md](feishu-second-app.md)
works for `.env` too). If the user pastes credentials directly in chat,
warn them about leakage risk once, write them to the file, and never
repeat the value in any output.

## v0.5 `/setup` routing matrix

The plugin routes `/setup` by (chatType, configured, descriptor shape,
operator identity). Read the matrix top-to-bottom; the first match wins.

| chatType | configured? | descriptor        | operator           | behavior                                                        |
| -------- | ----------- | ----------------- | ------------------ | --------------------------------------------------------------- |
| group    | no          | —                 | any allowlisted    | full setup card; ⌂ workspace-root option shown AND pre-selected as the default project |
| group    | yes         | bound_by present  | bound_by           | compact rebind card (mention toggle only)                       |
| group    | yes         | bound_by present  | other              | plain-text refusal                                              |
| group    | yes         | no bound_by       | allowlisted        | compact rebind card                                             |
| group    | yes         | no bound_by       | not allowlisted    | plain-text refusal                                              |
| p2p      | no          | —                 | owner (zero-config: any sender, only with explicit `FEISHU_DM_POLICY=open\|pairing`) | auto-spawn to defaultWorkDir (owner DM; see below)           |
| p2p      | no          | —                 | non-owner          | setup card (no ⌂)                                              |
| p2p      | yes         | bound_by==owner   | owner              | plain-text refusal — "This is the owner's DM, bound to …"       |
| p2p      | yes         | bound_by≠owner   | owner              | setup card (no ⌂) — descriptor drifted, let owner reassign      |
| p2p      | yes         | bound_by present  | non-owner          | setup card (no ⌂) — secondary DM flow                           |
| p2p      | yes         | no bound_by       | any                | setup card (no ⌂) — re-setup allowed                        |

The **⌂** ("workspace root") dropdown entry:

- **Owner DM** — bound automatically via auto-spawn (no card).
- **First-time group setup card** — shown AND pre-selected as the
  default project. A group whose workspace has no discovered
  sub-projects would otherwise present an empty dropdown, so clicking
  Start sent no project and the bind failed. With ⌂ as the default,
  clicking Start with no change binds the group to the workspace root;
  the operator can still pick a narrower sub-project from the same
  dropdown.
- **Secondary (non-owner) DMs** — hidden. These are guest accesses;
  exposing the root workspace would leak the whole project tree.

## Owner DM contract

The bot owner's DM is the **zero-prerequisite control surface**:

- First message on an unconfigured owner DM: plugin auto-spawns the
  channel to `defaultWorkDir` (daemon-handshake resolved) with the
  kind's default runtime (`kernel/config/feishu.md → runtime`, fallback
  `claude`). No card, no dropped message. The first message flows
  through ingress as normal.
- Setup cards only show runtimes that the daemon reported as available
  at boot. If Codex is missing from the card after installing codex, restart
  the daemon so the card list re-probes (message routing does not need it).
- Changing an existing chat's runtime through the setup card is refused
  while that chat's session is bound to another runtime; the refusal lists
  the sessions. `/clear` first, then re-run the setup card.
- **Pi is always listed, and "available" is not "ready".** Pi is
  embedded, so it never fails a probe — but it has no default model, and
  a pi session refuses every message until one is set. The bind
  confirmation carries the next step (`/model <provider>/<modelId>`);
  see [pi-runtime.md](../../duoduo-runtime-admin/references/pi-runtime.md).
- The owner is the open_id the plugin reads at startup:
  `FEISHU_BOT_OWNER` env → fallback `FEISHU_ALLOW_FROM[0]` → none.
- When there is none (zero-config), every DM is denied unless
  `FEISHU_DM_POLICY` is explicitly `open` or `pairing`; then ANY first DM
  sender triggers auto-spawn but `bound_by` is NOT persisted — see
  "Security hygiene" below.
- **Main claim.** A configured owner's DM on the default instance also
  claims the main role when nobody holds it (checked again at every start).
  Zero-config and named instances never claim. Role details:
  `duoduo-runtime-admin` → `references/main-session.md`.

After auto-spawn, `/setup` on the owner DM is refused. The DM is
locked to `defaultWorkDir` so the operator always has a working
control channel even if other bots/config break. To rebind the
owner DM, run the reset script. Moving the main role elsewhere needs no
reset: `duoduo-runtime-admin` → `references/main-session.md`.

## Security hygiene

Both access policies default to `allowlist`, and `FEISHU_BOT_OWNER` is
always admitted in direct messages. `FEISHU_DM_POLICY=open` or
`FEISHU_DM_POLICY=pairing` (they behave the same) admits every DM sender;
`FEISHU_GROUP_POLICY=open` admits every member of every group the bot is in.
Use either for bootstrap only.

Production `~/.config/duoduo/.env` should have:

```bash
FEISHU_BOT_OWNER=ou_yourOpenId       # explicit owner — locks the owner DM, lets it claim main
FEISHU_ALLOW_FROM=ou_you,ou_friend,… # extra DM senders; each may also use the bot in any group
FEISHU_ALLOW_GROUPS=oc_…             # groups the bot answers in (policy allowlist is the default)
FEISHU_GROUP_CMD_USERS=ou_you,…      # grants /setup in groups whose descriptor has no bound_by
```

### A new group (created with lark-cli or by hand)

Under the default group `allowlist`, a message in a group is admitted only
when the group's `chat_id` is in `FEISHU_ALLOW_GROUPS`, or when the sender's
open_id is in `FEISHU_ALLOW_FROM` (then only that sender, in any group).
`FEISHU_BOT_OWNER` alone does not reach groups. A denied message gets the
plain-text reply 「抱歉，您没有权限与此机器人对话。如需访问，请联系管理员。」.
The access check runs before the @mention check, so in an unlisted group
the bot sends that reply to every message it receives, mentioned or not.
For a new group the bot should answer:

1. Take the `chat_id` (`oc_…`) from the create response or from the chat.
2. Add it to `FEISHU_ALLOW_GROUPS` in the env file of the instance whose
   bot is in the group: `~/.config/duoduo/.env` for the default app,
   `~/.config/duoduo/feishu.<name>.env` for a named one (named instances
   inherit no `FEISHU_*` key from `.env`).
   - The key exists: append `,oc_…` to its value. Never drop an entry.
   - The key is absent: make sure the file ends with a newline, then add
     one `FEISHU_ALLOW_GROUPS=oc_…` line.
   - Never write a second `FEISHU_ALLOW_GROUPS` line.
   `duoduo-runtime-admin`'s
   [scripts/update_host_env.py](../../duoduo-runtime-admin/scripts/update_host_env.py)
   does both safely: read with `--file <env file> get FEISHU_ALLOW_GROUPS`,
   then write the full list with `--file <env file> set FEISHU_ALLOW_GROUPS
   <old>,oc_…` (`set` replaces the value in place).
3. Restart that instance (`duoduo channel feishu stop` + `start`, with
   `--instance <name>` for a named one); the lists are read at startup.
4. Check its startup line in `duoduo channel feishu logs [--instance <name>]`:
   `[policy] effective access policy` shows the new `allowGroupsCount`.

Ask the owner before adding a group: every member of a listed group can
use the bot there.

When the user reports "strangers can DM my bot", check for an explicit
`FEISHU_DM_POLICY=open` or `pairing` first. When the bot replies
「抱歉，您没有权限与此机器人对话。如需访问，请联系管理员。」, read the
`[policy] effective access policy` line in
`duoduo channel feishu logs [--instance <name>]`. When the user reports "/setup does nothing on my bot's DM",
check whether their open_id matches `FEISHU_BOT_OWNER` (the refusal
message says "This is the owner's DM, bound to …", which is the
intended behavior).

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

## Inbound files with text

Treat text and ordinary file attachments in one Feishu message as one input.
Rich-text (`post`) messages can carry ordinary files in a top-level `files`
attachment zone, separate from their paragraph content. Returned message entries
use `file_key` and `file_name`; the sender's `key` and `name` format is different.

The gateway downloads each ordinary file using the originating message ID,
uploads it to the daemon inbox, and delivers the text and readable attachment
paths together. Attachment-zone file names and MIME metadata are preserved.
Replying to an earlier post uses the same attachment recovery path. Folder
attachments are not expanded or submitted to the ordinary file download API.

When text arrives but its file is missing:

1. Run `duoduo channel feishu logs`. Check the matching ingress attachment count.
2. Check for `download+upload failed` or `empty media response` before that ingress.
3. If no download was attempted, inspect the message's raw `post` structure for
   the attachment zone as well as paragraph nodes. A screenshot cannot identify
   which representation the API delivered.
4. Older plugin builds may omit the attachment zone. After installing a build
   that includes the correction, run `duoduo channel feishu stop` followed by
   `duoduo channel feishu start` to load it.

## Outbound media rendering

The Feishu gateway renders daemon-produced attachments according to MIME:

- `audio/ogg` (`.opus`, `.ogg`) — sent as a **native Feishu voice note**,
  not a generic file attachment. This is the path agents should use for
  voice-message output. `.opus` is preferred because Feishu's audio player
  supports it natively at low bitrate.
- `audio/mpeg` (`.mp3`), `audio/wav` (`.wav`) — sent as generic audio file.
- `image/*` — sent as inline image.
- All other MIME types — sent as a file attachment.

When the agent calls `QueueOutboundAttachment` (MCP tool) with an `.opus`
file, the gateway uploads it as a voice message bubble that the user can
play with one tap. Useful for generated voice replies and audio summaries.

## Card footer

Every finished reply card carries a one-line ops footer:
`↑in(cache%) ↓out · ctx N · model · $cost`. Segments a runtime does not
report are simply omitted (a Codex turn has no cost, a compat endpoint may
have no context figure), so the line just renders shorter. The footer appears
when the reply finishes; the loading animation during generation is the
platform's, unchanged. A turn that reports no usage renders no footer. There
is nothing to configure.

## Process card

The process card replaces the streaming card and the per-stage reactions with a
layout modelled on Feishu's own agent. It is selected per channel by
`process_card` inside the `feishu:` block of the channel config:

```yaml
feishu:
  process_card: replace   # off (default) | replace | keep
```

- `off` — the streaming card path, unchanged. An absent or unrecognised value
  means the same thing.
- `replace` — one card: the process card becomes the answer when the turn ends.
- `keep` — two cards: the finished process card stays as a trace and the answer
  arrives as its own result card.

Put it in `config/feishu.md` to set every Feishu channel, or in one instance
descriptor to override that channel alone; the instance value wins per key. The
daemon reads both files on every message, so a change takes effect on the next
message — no channel restart and no daemon restart. Behaviour switches only
ever go in this block: its contents are handed to the channel with each
message, so credentials must never be written there.

What a turn looks like with the card on:

- **Reactions per turn: `Get` → removed.** Nothing else, so the author's phone
  rings once per turn instead of once per tool/typing switch. The working
  signal is the animated icon on the card's status line, not a reaction.
- **Process card**, sent as a reply on the first model signal: a collapsed
  panel titled 「工作中」 plus one status line (an animated icon, blank until
  the first line of text). The
  chat-list preview reads 「工作中」 too. Interim text streams into the status
  line one line at a time with the typewriter effect; each tool call (raw tool
  name plus a one-row summary, e.g. `Bash ls -la`) takes the panel title the
  moment the call starts and stays there until the next call. Every completed
  line of text and every tool call is archived inside the panel in order, so
  the expanded panel reads as a timeline. When the turn ends the panel is
  retitled 「任务已完成」 (「已停止」 after `/cancel`); Skip recalls the card.
- **The answer.** Under `replace` the process card is replaced in place by the
  answer when the turn ends (markdown plus the footer); the tool panel is
  gone, attachments
  follow the card, and a turn that ends with no text recalls the card.
  `/cancel` still leaves the 「已停止」 panel. Under `keep` the finished process
  card (「任务已完成」) stays and the answer arrives as a separate **result
  card**, so it can be forwarded without the process. A turn with no tool calls
  and no attachments ends as one card either way.
- Under `keep` the finished panel holds the interim text but not the answer's
  lines; the answer lives only in the result card.

Internal drains — a Notify wake, a job result, a turn a session scheduled for
itself — never get a process card: the card belongs to the message a person
sent. Their output arrives as plain text and leaves a card that is still being
written untouched.

The daemon side gained two optional fields on `session.execution`
(`anchor_event_id`, `is_sidechain`) in the same release; an older daemon still
works, but a reply may anchor to the newest inbound message instead of the one
the turn answers when several messages were merged, and subagent tool calls are
not hidden.

There is no scroll or max-height option on Feishu's collapsible panel; a long
turn expands to its full step list. This is deliberate.

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
require_mention checker, and `duoduo channel feishu doctor`
includes it in the manual checklist. If a user toggles the box but
group messages still need @, this scope gap is the most likely cause.

## Web search/fetch disabled by default

A Feishu agent asked to look something up will appear to "have no internet" —
`WebSearch` / `WebFetch` are not on the default tool surface (headless
daemon), so the model loops WebSearch → WebFetch → `curl` → gives up. This is
policy, not a defect. Enable them in `config/feishu.md` frontmatter (or an
instance descriptor):

- v0.5.10+: add to the nested `claude.tools` key —
  `claude:` newline `  tools: [WebSearch, WebFetch]`
- ≤ v0.5.9: add to `allowedTools` (the old denylist-override recipe; it no
  longer works on v0.5.10+)

See [channel-config-model.md](channel-config-model.md) for the allowlist
core, merge semantics, and the ≤ v0.5.9 migration notes.

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

The owner-DM refusal gate requires a configured owner
(`FEISHU_BOT_OWNER`, or the first `FEISHU_ALLOW_FROM` entry), read once at
plugin startup. If the operator accidentally
unsets `FEISHU_BOT_OWNER` in `.env` (typo, deletion) and restarts,
the owner-DM lock lifts — their own `/setup` falls through to
the secondary card and can reassign the DM.

This requires shell access, `.env` edit, and a restart — equivalent
to running the reset skill directly. Config-hygiene issue, not an
attack vector. Recovery: restore `.env` and restart.
