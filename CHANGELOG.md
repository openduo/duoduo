# Changelog

All notable changes to this project will be documented here.

## [v0.8.8] - 2026-11-05

A session can now ask someone in a Feishu chat a question and get the answer
later, and the main session hands long work to jobs so the next person who
writes to it is not kept waiting.

Upgrading means reinstalling core (0.8.8) and the Feishu channel (0.8.8), then
restarting the daemon and every Feishu instance. Protocol (0.8.6) and the ACP
channel (0.8.3) are unchanged. The bundled agent SDK moves to `^0.3.318`
(Claude Code 2.1.318); pi moves to 1.5.0.

Behaviour changes to know about:

- **The main session dispatches long work.** Work that would keep main busy
  for minutes — a build, a multi-step change, research — goes to a job that
  notifies main with the result; quick work stays in main. For a request from
  a forwarded chat, main leaves the message's received mark in place until the
  result is back, then answers it with `send --reply-to`. The first turn after
  the upgrade pays the one-time cost of a role-text change.
- **Subagent effort (Claude Code 2.1.317).** A subagent running on a model
  other than its session's uses that model's own effort setting or its
  default, not the session's. `CLAUDE_CODE_SUBAGENT_EFFORT` sets it.
- **pi 1.5.0 tightened its system prompt.** The tools section pi sessions keep
  in override mode now ends with "Additional tools may be available."

### Features

- **Ask a chat with a question card.** `duoduo channel feishu ask --chat
  <chat_id> --who <@name|owner|anyone|ou_…> --question "<text>" --context
  "<text>|-"` posts a card with buttons (`--option`, once per choice), a
  multi-select (`--multi`), a text field (`--text <label>`), or a mix. The
  first valid answer replaces the card for everyone with the question, every
  option offered (the chosen ones marked) and, in a group, who answered. The
  answer returns to the asking session as a notification carrying its
  `--context`, so the session ends its turn after asking. A card for the
  owner, or for a name that matches nobody or several people, goes to the
  owner's direct messages with a line naming the session and the chat. Cards
  expire after 14 days, or sooner with `--expires`. Only a chat's forward
  target or the chat's own session can ask there; `ask` from a terminal is
  refused. `ask --help` explains the rest. Card text follows
  `FEISHU_LOCALE` (Chinese or English).

### Security

- **Dependency advisories cleared.** follow-redirects moves to 1.16.2
  (GHSA-mrwp-f3q8-3g9p, high; reached through the Feishu SDK's HTTP client).
  pi 1.5.0 pins undici 8.12.3, so the undici 8.10.2 copy noted in v0.8.7 is
  gone.

### Updates

- **Agent SDK 0.3.318** (Claude Code 2.1.318). See the behaviour changes above.
- **pi 1.5.0.** Tool arguments are validated by pi's own schema library; the
  new sibling package `@earendil-works/pi-schema` is pinned with the rest.

## [v0.8.7] - 2026-10-30

One duoduo, several faces: a host now has a main session where everything
without another home converges, the Feishu channel can run a second app (a
second enterprise, or Feishu and Lark side by side), and any chat can be
forwarded to an existing session instead of getting a session of its own.

Upgrading means reinstalling core (0.8.7), protocol (0.8.6) and the Feishu
channel (0.8.7), then restarting the daemon and every Feishu instance. The
ACP channel (0.8.3) is unchanged. The bundled agent SDK moves to `^0.3.312`
(Claude Code 2.1.312); pi stays at 1.4.0.

Behaviour changes to know about:

- **Every channel session gets a role.** The session aliased `main` reads a
  short main-role text, every other channel session a member-role text. The
  first turn after the upgrade pays a one-time cost, as a system-prompt change
  does: Claude sessions restart their process, Codex threads fork once, pi
  recycles its worker. A warm Grok session keeps its old role text until its
  next cold start.
- **Notify to a connected channel is no longer refused for slow reading.** A
  channel session whose plugin holds a live connection counts as reachable,
  however long its last reply has waited unread. This is what lets a tether
  assistant that reads its mail once a day receive mail without `--force`. A
  session with no live connection is judged as before.
- **Long foreground `sleep` is blocked in more places.** Claude Code 2.1.310
  refuses a standalone `sleep` also when telemetry or non-essential traffic is
  off, which duoduo sets on hosts with a configured model endpoint. Sessions
  there now see the refusal; `run_in_background` is the way to wait.
- **Automatic model switch after a flagged message now covers custom model
  names** (Claude Code 2.1.312), such as gateway deployment names. duoduo keeps
  this upstream behaviour; set `CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK=1` in the
  daemon environment to turn it off.

### Features

- **Main session.** One channel session holds the alias `main`; Notify takes
  `main` as an explicit target and resolves it at each delivery. A job outcome
  whose owner cannot take it goes to main, marked as a stand-in delivery. On a
  Feishu host the owner — `FEISHU_BOT_OWNER`, or the first entry of
  `FEISHU_ALLOW_FROM` — claims an empty main role with their first DM; an
  existing owner DM is also recognized as main when the default instance
  starts and main is empty. A named instance never claims main. Elsewhere
  `duoduo session alias <key> main --move` sets or moves it. `duoduo session
  list` marks it, and `--json` rows carry `main` and `main_since`; `duoduo
  daemon status` lists the sessions when more than one is aliased `main`. A
  channel session can no longer take `main` as its display name any other
  way. The session is told when it becomes main and tells its owner in its own
  words.
- **A second Feishu or Lark app.** `duoduo channel feishu <verb> --instance
  <name>` runs another app beside the default one, with its own credentials in
  `~/.config/duoduo/feishu.<name>.env` (mode 0600) and its own state.
- **Forwarded chats.** `duoduo channel feishu forward --chat <chat_id> --to
  <session|main>` hands a chat to an existing session; `--clear` gives it back.
  Each forwarded chat keeps an append-only log the session reads itself, with a
  short id per message. A mention wakes the session with the addressed message,
  the log's path and the unread range. The bot marks an addressed message as
  received; if the session cannot be reached, the bot says so in the chat.
- **Answering a forwarded chat.** `duoduo channel feishu send --chat <chat_id>
  --reply-to <id|none> (--text <t> | --file <path>)` posts as the bot. Text
  renders as Markdown like a normal reply; a message id quotes that message and
  clears its received mark; `none` posts a new message. Only the session the
  chat is forwarded to, or an operator, can send there. `send --help` explains
  the rest.
- **Hand a group to an existing session from its setup card.** The setup card
  gains a choice that asks the main session to take the chat; the owner decides
  where it goes.

### Security

- **Dependency advisories cleared in duoduo's own dependencies.** undici moves
  to 8.12 (high-severity advisories including a TLS certificate validation
  bypass and cache poisoning), zod to 4.6.7 (memory exhaustion), and the MCP SDK
  to 1.32.2, which brings body-parser, qs, fast-uri and the Hono server adapter
  past their advisories. pi 1.4.0 pins undici 8.10.2 for itself; an npm install
  still places that copy under pi until pi publishes a fixed pin.
- **Forward and send are bound to the forward.** A forwarded message's text
  never authorizes moving the main role, changing a forward, or sending into
  any chat other than the one it came from; `send` resolves message ids only
  within the chat it is sending to.

### Updates

- **Agent SDK 0.3.312** (Claude Code 2.1.312). See the behaviour changes above.
- **Skip texts name what was withheld.** The Skip tool and the notice after a
  skipped turn now say that the turn's text reply was not delivered, rather
  than everything the turn did; tool calls before Skip, such as a `send`,
  still take effect.
- **Uploads over `/rpc` match WebSocket.** The full-access HTTP `/rpc` body
  limit now equals the WebSocket message limit, so an upload that works over
  WebSocket also works over `/rpc`.
- The tether channel 0.2.5, released alongside this version, tells the main
  session about each newly connected assistant and returns its full text to
  clients that read only a tool result's structured part.

## [v0.8.6] - 2026-10-23

A security release: every open dependency advisory is cleared, the bundled
agent SDK and pi move to their latest releases, and the install no longer
pulls an unreviewed major version of a transitive package.

Upgrading means reinstalling core (0.8.6) and the Feishu channel (0.8.6),
then restarting the daemon and the Feishu channel. Protocol (0.8.5) and the
ACP channel (0.8.3) are unchanged. The bundled agent SDK moves to `^0.3.309`
(Claude Code 2.1.309), and the bundled pi moves from 1.2.0 to 1.4.0.

Behaviour changes to know about:

- **Fork subagents stay off.** Agent SDK 0.3.302 started offering "fork"
  subagents by default: a subagent that inherits the whole conversation and
  always runs on the parent session's model. duoduo turns them off for every
  Claude session in this release, so the tool surface and per-turn cost are
  the same as in v0.8.5. Enabling them is planned once their cost and
  delivery behaviour have been measured.

### Security

- **Feishu channel: credential headers on cross-origin redirects.** The
  HTTP redirect library bundled into the Feishu gateway moves to 1.16.1,
  which fixes two high-severity advisories (GHSA-q3jh-wrc6-jgq8,
  GHSA-8r9p-f939-6h3c) where authorization headers could survive a redirect
  to another origin. Exploiting it needed the Feishu API itself to redirect
  elsewhere.
- **Agent SDK 0.3.309** extracts its embedded Claude Code binary into a
  per-user temporary directory and reuses an extracted copy only when its
  bytes match, instead of a temporary directory shared with other users.
- **Bounded `@anthropic-ai/sdk` on npm installs.** The agent SDK declares
  this package as an open-ended peer dependency, so `npm install -g` pulled
  whatever release was newest, including a new major. duoduo now declares it
  directly with a bounded range.
- Fastify moves to 5.12.7 (a low-severity header validation advisory; no
  duoduo route used the affected feature). The remaining advisories
  `npm audit` reported were in development tooling or in code paths that are
  not part of the published packages; those dependencies are updated too.
- The release pipeline pins its third-party build steps to exact commits and
  no longer requests a package-registry write permission it did not use.

### Updates

- **pi 1.4.0.** No settings changes are needed. Notable upstream fixes:
  sessions recover after a response is cut off at the output limit, and
  compaction summaries no longer fail on long reasoning. See pi's release
  notes.

## [v0.8.5] - 2026-10-13

A maintenance release: dependency and security updates, two Feishu fixes, and
a stricter job working-directory check. The published packages now carry a
license.

Upgrading means reinstalling core and protocol (0.8.5), the Feishu channel
(0.8.5) and the ACP channel (0.8.3), then restarting the daemon and both
channels. The ACP channel's only change is that it ships the license files.
The bundled agent SDK moves to `^0.3.296` (Claude Code 2.1.296), and the
bundled pi moves from 1.0.4 to 1.2.0.

Behaviour changes to know about:

- **An invalid job `cwd_rel` is refused.** Up to v0.8.4 a job whose
  `cwd_rel` was an absolute path or pointed outside the work dir (possible
  only in a job file edited by hand) ran silently in a system scratch
  workspace, without its project `CLAUDE.md`. It now fails each run with
  `invalid cwd_rel path`. The `duoduo-admin` skill's upgrade playbook has the
  command that lists every job's `cwd_rel`.
- **Feishu process card: the working signal is an animated icon.** The card's
  status line carries an animated icon instead of 「思考中...」, and the
  `THINKING` reaction is gone: reactions per turn are `Get` when the message
  arrives, removed when the turn ends. One notification and two API calls
  fewer per turn.

### Highlights

- **License.** Every published package (`@openduo/duoduo`,
  `@openduo/protocol`, `@openduo/channel-feishu`, `@openduo/channel-acp`) now
  ships `LICENSE` (FSL-1.1-Apache-2.0) and `LICENSE.agents.yaml`, an addendum
  that states the terms for agents reading or modifying the installed bundle.
  Earlier releases carried no license.
- **Longer MCP tool descriptions reach the model.** With agent SDK 0.3.296,
  Claude Code cuts an in-process MCP tool description at 4,096 characters
  instead of 2,048, so duoduo's longer tool descriptions are no longer
  truncated.
- **pi 1.2.0.** No settings changes are needed. If you run your own pi
  extensions, note that pi 1.2.0 also fires `before_agent_start` for runs an
  extension starts; see pi's release notes.

### Fixes

- Fresh installs and reinstalls of v0.8.4 got a pi runtime that crashed on
  load: pi's companion packages had moved to a newer release that the
  bundled pi could not run with, so sessions, jobs and partitions on the
  pi runtime failed to start. v0.8.5 pins those packages to the same release
  as the bundled pi, so later pi releases can no longer be mixed in.
- Feishu rich-text (`post`) messages keep their ordinary file attachments.
  Files in the message's attachment zone were dropped, so the text arrived
  without them; they are now downloaded and delivered with the text,
  including when the message is the parent of a reply.
- A job `cwd_rel` inside a directory whose name begins with two dots (such as
  `..x`) was treated as outside the work dir. It is now accepted.
- `@modelcontextprotocol/sdk` moves to 1.32.1, which clears the high-severity
  advisory GHSA-6qxp-vccf-f47h.

## [v0.8.4] - 2026-10-06

A runtime value duoduo does not know is now refused instead of silently
replaced. Up to v0.8.3 a typo such as `runtime: codx` was dropped without a
word: a channel or partition fell through to the next layer (instance, then
kind, then the global default), and an invalid `ALADUO_DEFAULT_RUNTIME` fell
back to Claude. The sessions kept answering, often on a runtime no one chose.
From v0.8.4 the value is refused with a sentence that names it and lists the
valid ones.

Upgrading means reinstalling core and protocol (0.8.4) and the Feishu channel
(0.8.4), then restarting the daemon. The Feishu channel's only change is that
its setup card labels the new `void` runtime. The ACP channel is unchanged and
stays on 0.8.2. The bundled agent SDK moves to `^0.3.291` (Claude Code
2.1.291), and the bundled pi moves from 0.85.1 to 1.0.4.

Behaviour changes to know about:

- **Check every written runtime value before upgrading.** After the upgrade an
  unknown value in `ALADUO_DEFAULT_RUNTIME` stops the daemon from booting (an
  absent or empty value still means `claude`). In a channel kind or instance
  descriptor it refuses the turns of the sessions that layer selects; a valid
  instance value still overrides an unknown kind value. In job frontmatter the
  job fails, and in partition frontmatter the partition is skipped. Fix a
  misspelled value to the runtime those sessions have actually been running
  on, which is not necessarily Claude. The `duoduo-admin` skill's upgrade
  playbook has the commands that find every written value.
- **pi's DeepSeek Flash id is renamed.** pi 1.0 no longer has
  `deepseek/deepseek-v4-flash` in its built-in catalog; the id is now
  `deepseek/deepseek-flash`. Any model pin that names the old id fails to
  resolve: partition or job frontmatter, channel config, or a stored `/model`
  choice. Change a stored choice by sending `/model deepseek/deepseek-flash`
  in that session.
- **Claude Code's own auto memory is off** in every Claude session duoduo
  starts, because it would keep a second memory store beside duoduo's.
  Nothing migrates. An `env` entry for `CLAUDE_CODE_DISABLE_AUTO_MEMORY` in a
  Claude settings file the session loads (for example the user-scope
  `~/.claude/settings.json`) still wins.
- **Resumed Claude sessions report their own cost.** The first Claude turn
  after a session's process restarted (idle reclaim, daemon restart) used to
  report the session's lifetime cost and most-used model as that one turn's,
  in the footer and in the usage ledger. A resumed turn now reports its own
  figures. A session that existed before the upgrade has no saved baseline
  yet, so its first resume shows no cost and no model. Ledger records written
  before the upgrade keep their old values.
- **pi 1.0 extensions.** Extensions are now loaded against pi 1.0. A run that
  an extension defers from `agent_settled` during a turn now counts toward
  that turn: its text and usage belong to it. A pi session file is now
  written at the first user message, so a crash during the first turn resumes
  a session that holds that message, still unanswered.

### Highlights

- **`duoduo session notify` inside a session sends as that session.** Run
  from a session's own shell, the message is recorded with that session as
  the sender, as the `Notify` tool already did, so the recipient sees which
  session sent it. A shell outside any session keeps the old source
  label.
- **Subconscious: second-hand reports stay second-hand.** The
  `gradient-distiller` and `intuition-weaver` prompts treat another
  assistant's report of its conversation with the owner as second-hand.
  Words about the owner are a claim, not the owner's ruling. A change to who
  receives something, a credential, a permission, or what sessions run needs
  the owner's explicit yes on a first-hand channel before it reaches the
  board. An upgrade never overwrites existing partition prompts, so nothing
  changes until you refresh them; the `duoduo-runtime-admin` skill walks it.
- **For channel plugin authors:**
  - A new runtime value, `void`, for channel plugins whose sessions never run
    a model. A message to a void session is written to the spine and the
    outbox and wakes nothing. Model commands (`/model`, `/effort`,
    `/compact`) refuse it. `void` is not accepted as the default runtime, a
    job runtime or a partition runtime, and should not be set on an ordinary
    chat channel.
  - `channel.spawn` takes an optional `session_key` and creates that session
    bound to the channel.
  - `channel.pull` accepts `advance: "ack"`: the stream pushes records as
    before, and only `channel.ack` moves the consumer's cursor.
  - `spine.record` appends an `external.record` event for writers outside
    duoduo, with optional per-source deduplication. `spine.cat` takes
    `redact: "external"` for readers outside duoduo.
  - `session.list` accepts `deliverable: true` to list only the sessions a
    `Notify` would deliver to.

### Fixes

- `duoduo spine show --json` is accepted (and ignored) instead of failing.
- `channel.ingress` and `channel.command` validate `channel_id` before they
  bind the session. A malformed id used to rebind an existing session to it
  and was refused only afterwards.
- `channel.spawn` never moves a session to another channel. Naming a session
  that another channel owns is refused before anything is written.
- A message sent while a Claude subagent was running could be taken by the
  subagent's first tool call: it was marked as handled and injected into the
  subagent's conversation, which owns no reply, so the main session never
  answered it. It now waits for the main session's next tool call or the end
  of the turn.
- The `brace-expansion` and `source-map-js` advisories are cleared. Both were
  development dependencies only.

## [v0.8.3] - 2026-09-23

Claude Opus 5.5 works. It needs Claude Code 2.1.280 or newer, and 0.8.2 ships
2.1.278, so every turn on `claude-opus-5-5` failed with `400 ... version
2.1.280 or newer is required`. The bundled agent SDK now moves to 0.3.280, and
it is declared as a range (`^0.3.280`) instead of an exact version. A fresh
install picks up the newest 0.3.x, so the next model Anthropic ships should
need a reinstall, not a new duoduo release.

Upgrading is routine: reinstall core, restart the daemon. The Feishu and ACP
channels are unchanged and stay on 0.8.2.

Three behaviour changes to know about:

- **A Codex session no longer falls back to Claude.** When the Codex CLI was
  missing or failed its first check, a `runtime: codex` channel used to run on
  Claude for the rest of the daemon's life, with one warning in the log. It
  now refuses with `runtime_unavailable`, like Grok and Pi already did. A
  failed check is no longer remembered either: the next message checks again,
  so installing Codex takes effect without a restart.
- **Changing a session's runtime needs `/clear` first.** A session is now bound
  to the runtime that created its history. Pointing it at a different runtime
  used to hand one harness's session id to another: Claude and Codex silently
  started a new conversation, Grok failed every turn, Pi opened an empty
  history. duoduo now refuses the switch with `runtime_mismatch`, naming both
  runtimes. `/clear`, then change the runtime.
- **`ManageJob` requires `action`.** A call without it used to be answered
  with the job list and no error, so a `create` whose `action` was dropped on
  the way (some Anthropic-compatible gateways re-serialize tool input) looked
  like success (#79). It is now an error on every runtime.

### Highlights

- **Claude Opus 5.5.** `claude-opus-5-5` and `claude-opus-5-5[1m]` are accepted
  by `/model`, and a session that names them runs.
- **Effort `max`.** `max` is now a valid effort level everywhere effort can be
  set: `/effort`, `duoduo session`, job frontmatter, `ManageJob`, the
  per-runtime defaults and partition frontmatter. On a Claude model without
  `max` support the request runs as `high`, and the `/effort max` reply says
  so.
- **Dashboard shows reminders correctly.** A reminder set with `RemindDuoduo`
  appeared in the job list as `cron: ? / unknown · 0 runs / last: never`. It
  now shows its owner, when it fires, when it was set, and what it says.

## [v0.8.2] - 2026-09-20

Mostly about being told when something did not happen. A notification sent into
a session nobody is reading is now refused instead of disappearing, a session
can schedule its own next turn, and ending or re-timing a job is a shell verb
rather than a tool call. Underneath, the agent SDK and the dependency tree both
move forward.

**Reinstall the channels too.** The Feishu gateway bundles its dependencies and
carries its own copy of a package this release patches, and the ACP bridge has
a fix of its own — neither reaches a host through the core upgrade. Install
`@openduo/channel-feishu@0.8.2` and `@openduo/channel-acp@0.8.2`, then stop and
start each channel. Otherwise upgrading is routine: reinstall, restart the
daemon.

Three behaviour changes to know about:

- **A tool was renamed.** `Wake` is now `RemindDuoduo`, and `ManageSession` is
  now `ViewSessions`. Records, blocks and CLI verbs still say wake. A Codex
  session sees the new names only after `/reset`.
- **`ManageJob` no longer ends or re-times a job.** It keeps creating, listing
  and reading them; archiving, interrupting and rescheduling moved to
  `duoduo job`. This is deliberate — those are operator actions, and an agent
  reaching for them mid-turn was usually a mistake.
- **`duoduo daemon enable-autostart` and `disable-autostart` are gone.** They
  did not do what their names promised on either platform.

### Highlights

- **Notify refuses a session nobody reads.** Delivering into a foreground
  session whose last consumer take is older than
  `ALADUO_NOTIFY_UNCONSUMED_HOURS` (default off until set) now fails with a
  message naming the sessions that *do* have a reader, instead of writing into
  a void. `--force` overrides it. `duoduo daemon status` grew a block listing
  each channel session's last consumer take and its current subscribers, so the
  state behind a refusal is visible before you hit one. A job's own completion
  notice still reaches its owner regardless.
- **A session can schedule its own next turn.** `RemindDuoduo` books one future
  turn of the calling session — no key, no target. For a job session it is one
  more fire of its own schedule. Cancel a pending one with
  `duoduo job archive <id>`.
- **Job lifecycle from the shell.** `duoduo job list | read | archive |
  interrupt | reschedule`. Interrupting carries a reason, and the reason opens
  the job's next run, so the session learns why it was cut off rather than
  guessing.
- **The model is told when a human ended its turn**, instead of the turn simply
  stopping and the next one starting from a gap it cannot explain.
- **`duoduo --version` answers without a daemon.**

### Ecosystem

- **The ambient channel and a reference backend for it are open source**, in
  their own repository at `openduo/ambient`. Ambient is a room-listening
  surface: duoduo hears what is said near it and decides whether it was
  addressed. The backend published alongside it is a reference implementation —
  enough to run the channel end to end and to build a different one against.
  Nothing in this release depends on it; `@openduo/duoduo` ships exactly the
  four packages it always has.

### Runtime and dependencies

- **Agent SDK 0.3.278** (from 0.3.266). Two upstream changes reach duoduo:
  - Switching a session to a model id the CLI does not recognize now takes
    effect on the next turn, at the cost of one restart of that session's
    process, instead of being acknowledged and then quietly ignored for the
    life of the process. History is preserved across the restart.
  - The built-in tool for polling a background agent's output was withdrawn
    upstream and is no longer offered to sessions. Background agents report
    when they finish, which is the mechanism duoduo already used.
- **Dependency refresh** across the tree — Fastify, undici, zod, cron-parser,
  the Feishu SDK and the dev toolchain. No advisory was outstanding against
  this tree before or after; this keeps it that way.

### Fixes

- The daemon tolerates a torn dedup line instead of failing the read, writes
  every `.env` at `0600`, and guards the by-id index against out-of-range
  lookups.
- A channel waits for a pending ingress before deciding which turn a reply
  belongs to — a slash command sent onto a live process card no longer detaches
  from the message that triggered it.
- The Feishu process card prefers a step's description over its raw command, so
  a turn's shell activity reads as statements rather than command lines.
- Grok reports context occupancy from the sibling last-call total, so the
  footer stops under-reporting.
- `duoduo session wake` refuses the kernel plane rather than accepting a target
  it cannot reach, and `duoduo job read` renders a scheduled wake.
- The dashboard streams usage summaries and bounds event tail reads.
- Several CLI messages corrected to state what actually happened: where a
  handled mark lands, which id a failure suggests re-running, and a stdio
  client-setup rejection surfacing as an error instead of an unhandled
  rejection.

## [v0.8.1] - 2026-09-09

duoduo now owns which model and how much reasoning effort each runtime gets,
instead of inheriting whatever the underlying CLI happened to be configured
with. The dashboard was rebuilt on the OpenDuo design system. The rest is
fixes and a dependency refresh: the agent SDK, pi, and security updates across
the whole tree.

**Reinstall the Feishu gateway too.** Its source is unchanged, but it bundles
its dependencies, so it carries its own copy of one of the packages this
release patches — the fix does not reach it through the core upgrade. Install
`@openduo/channel-feishu@0.8.1` and stop then start the channel. The ACP bridge
is genuinely unchanged and stays at 0.8.0. Otherwise upgrading is routine:
reinstall, restart the daemon. Two behaviour changes to know about:

- **Sessions may switch model on upgrade.** If you set a model default for a
  runtime, duoduo's own default now wins over the underlying CLI's config for
  duoduo sessions. Set nothing and the previous behaviour is unchanged. On
  Codex, a live conversation whose model changes forks once at its next turn —
  history is preserved.
- **Partition and job prompt edits are picked up again.** Edits that preserved
  the file's timestamp (`cp -p`, `ditto`, editors that restore times) used to be
  invisible to the running daemon until a restart. They now take effect at the
  next tick.

### Highlights

- **Model defaults you own, per runtime.** Set a default model for Claude,
  Codex, pi or Grok, globally or per channel kind or per channel instance, with
  the most specific layer winning. The dashboard and the usage ledger record the
  model that actually served each turn, not the one that was requested — so a
  gateway quietly substituting a model is visible instead of invisible.
- **Effort defaults, the same shape.** Reasoning effort gets the same
  global → kind → instance layering as the model, so a session's effort no
  longer depends on the underlying CLI's own configuration file.
- **The dashboard, rebuilt.** Restyled on the OpenDuo design system at the same
  structure and density, with click-to-filter on the stream and a strip of
  pinned facts under the stream title.

### Fixes

- A message you send while the agent is mid-turn on something it started by
  itself now gets its own turn. It used to be folded into that turn, which could
  produce a reply that was discarded outright.
- A finished job's completion receipt now arrives as context on the owner's next
  turn instead of waking a turn of its own.
- Job scheduling and dispatch: a run settles against the definition it started
  with rather than one edited mid-flight, and the wording of job receipts now
  states what delivery actually does — a job produces no turn of its own, a
  daemon restart delivers nothing, so do not promise to follow up.
- pi: worker generations no longer overlap, a batch survives an abort the worker
  never engaged, and a provider error that pi settles without raising is now
  surfaced instead of arriving as an empty answer.
- Subconscious partitions running on Claude honour a configured model profile,
  so naming a routed model in a partition no longer fails at the endpoint.

### Dependencies and security

- Agent SDK 0.3.258 → 0.3.266, pi 0.84.4 → 0.85.1.
- Security updates across the dependency tree: every high-severity advisory is
  resolved, and the one remaining moderate has no upstream fix and sits in a
  code path this project never executes. The Feishu gateway is republished at
  0.8.1 for this reason alone — a bundled gateway does not inherit a fix from
  the core package, it has to be rebuilt and reinstalled.
- duoduo now explicitly opts out of the agent SDK's new system-prompt recording
  default. With recording on, a conversation freezes its system prompt and tool
  definitions at its first request and replays them until it compacts — which
  would silently stop prompt and memory-board edits from ever reaching a running
  session.

## [v0.8.0] - 2026-09-04

pi joins Claude, Codex and Grok as a fourth agent runtime. `duoduo spine` opens
the write-ahead log as something an agent can actually read. The subconscious
memory pipeline was split in two and given a feedback signal, so it can tell
which of its own memories are doing any work. Feishu answers now stream into
the card you are already looking at instead of arriving as a second one.

**Upgrading is routine** — reinstall, restart the daemon, then reinstall and
restart your channels as usual. Two things to know before you do:

- Two `ALADUO_EXP_FEISHU_*` environment gates are **deleted, not renamed**. The
  behaviour they guarded now ships on, selected per channel. See the upgrade
  playbook in the `duoduo-admin` skill.
- The `memory-weaver` subconscious partition is **replaced** by two partitions.
  Existing partition prompts are never overwritten by an upgrade, so nothing
  changes until you refresh them — the `duoduo-runtime-admin` skill walks it.

### Highlights

- **pi is a first-class runtime.** Fourth peer behind the same seam as the other
  three: duoduo's own tools reachable from it, mid-turn steering, the same
  kind/instance/job/partition prompt fields including append-or-replace, and
  token accounting that understands pi's own reporting shape. `/model` lists the
  models *this* installation can actually run — resolved from the providers and
  extensions your pi has, not from a list we hardcoded — and a job naming a
  model pi cannot run is refused when you create it, not when it next fires.
  Subconscious partitions can opt into pi per partition. Availability fails
  closed: asking for pi when pi is not usable is an error, never a silent
  fallback.
- **`duoduo spine` — the log, readable.** The write-ahead log has always been the
  system's source of truth and has always been raw JSONL. This is a read surface
  built for an agent reading it: tool calls folded together with their results,
  full text rather than truncated previews, counts in a header and footer so a
  reader can tell a complete read from a partial one, and turn-granular resume
  (`--after`) so a long scan continues where it stopped instead of starting over.
- **The memory pipeline learned what it is not using.** The single memory weaver
  is now two partitions with separate jobs — one distils raw experience into
  fragments, one consolidates them into intuition. On top of that sits an
  activation report: it counts which memories are actually being read during
  real work, so the pipeline gets told about dead weight and unreachable
  material instead of accumulating both silently. Weaver wakes are now bounded
  by budget and rank everything waiting, rather than taking one item per wake.
  The activation window counts days on which someone actually interacted, so a
  quiet week no longer ages memories out.
- **Feishu: one card, not two.** The process card streams status while the turn
  runs, names the tools as they are called, and then the answer replaces it —
  no second card, and the footer is now standard rather than experimental.
  Selected per channel, so two channels on one daemon can differ. A card only
  ever appears for turns that channel itself started.
- **Model and effort from the CLI.** `duoduo session model` / `duoduo session
  effort` inspect or set a channel session's model and reasoning effort without
  going through the chat, and partitions can declare effort in frontmatter.
- **`duoduo daemon status` shows what is running right now.** With tool calls in
  flight it lists each one — which session, which tool, how long ago it started
  — and nothing when idle. Deliberately judgment-free: no threshold, no
  watchdog, no timeout. It reports; `/cancel` acts. Note that an empty list is
  not "nothing is happening" — it is equally empty while the model is writing.
- **The log index no longer grows forever.** The by-id index is now a bounded
  recency cache keyed on event date and compacted at boot
  (`ALADUO_SPINE_INDEX_RETENTION_DAYS`, 7 days by default). On a busy host this
  is the difference between a 157 MB index and a 5.6 MB one. Readers that miss
  it fall back to the day's log partition, so nothing becomes unreadable — and
  `duoduo spine show <id>` falls back to a full scan.

### Ambient — duoduo in the room

Ambient is duoduo present in a physical room: round-the-clock ears and eyes,
no app to open, no button to press, no wake word to recite before every
sentence. You talk. It is already listening, and it already knows whether you
were talking to it.

That last part is the whole trick, and it is why ambient is not a smart speaker.
A speaker asks "did this person stop talking?" Ambient asks a much harder
question — **"was that said to me?"** — and answers it the way a person sitting
in the corner of the room would.

A scene that happens constantly, and that nothing else gets right:

> Two colleagues are at the whiteboard arguing about duoduo. One says duoduo
> handled yesterday's rollout badly. The other disagrees, and for four minutes
> they go back and forth about what duoduo should have done.
>
> **duoduo says nothing.** Not a chime, not a "did you mean me?", not a
> half-second of a listening animation. Being *talked about* is not being
> *talked to*, and it sat through the entire argument without interrupting once.
>
> Then one of them turns to the corner: *"duoduo, what do you think?"*
>
> It answers — about the actual argument. Both positions, who said which, the
> rollout they were describing. It had been listening the whole time; it simply
> had no standing to speak until someone gave it one.

The same judgment runs in the other direction, which is the half everyone else
forgets. Command-shaped speech is not automatically an order: people dictate to
their phones and to other assistants in exactly the phrasing they would use on
duoduo, and being overheard is not being instructed. Retelling a past
conversation, thinking out loud, asking a rhetorical question, telling a third
party what to do — a person in the room would not answer any of those, and
neither does ambient.

Everything anyone says still becomes part of the room's record, whether or not
it was addressed to duoduo — that record is how it reads the room later. The
addressee judgment decides only whether it *acts*. Recording always happens; it
is not a behavioural choice.

Underneath it is one specialized multimodal model, end to end. Room audio goes
straight in; transcript and speaker attribution come out together, in a single
pass. That is why a five-person conversation arrives already attributed instead
of as one undifferentiated blob, and why the same person keeps one stable
identity through the day without ever enrolling a voice sample.

And it is small. It runs on hardware you already own — a Mac, a 3090, any
40-series card. **The room's audio never leaves the building.** A room full of
people talking all day is the most sensitive recording there is, and it can stay
on your own machine precisely because the model doing the hearing was built for
this one job and nothing else.

Around it: continuous voice-presence detection rather than push-to-talk or a
per-sentence wake word, and answers spoken with pauses placed where the
*reasoning* paused, not where a sentence happened to end.

Test access is open by application. If you want a room, open an issue
describing your space and how many people are usually in it.

### Fixes

- Shutdown now actually waits for work in progress. A daemon restart could
  start a fresh model turn after shutdown had begun, and outlive its own wait;
  in-progress deliveries, cursor writes and socket callbacks could all be
  dropped on the way out. When shutdown does give up on a turn that is taking
  too long, it now says so and names the sessions — previously that was silent
  and indistinguishable from a slow boot.
- Log lines containing U+2028 were shredded on read, because the line reader
  treated it as a line break and JSON does not. Any event carrying that
  character in its text was unreadable.
- A session woken while the runtime pool was full fell through into a drain
  instead of returning to wait, bypassing the pool cap.
- Identical text sent twice was silently suppressed as a duplicate. Ingress
  de-duplication now keys only on an explicit source id, so resending a message
  always gets an answer.
- A Feishu channel could reply twice while a CLI client was pulling the same
  session.
- A pi worker was torn down and rebuilt when its settings file merely failed to
  *read* — a transient error was treated as "not configured".
- A failed Grok availability probe reported a login problem regardless of the
  real cause.
- A partition that threw lost the error message on the way to the log.
- Job results went nowhere when the job had no explicit audience; the owner is
  now the default, and a job can no longer disappear without a trace.
- Two log lines that restated a record already on disk, and a housekeeping
  warning that fired once per orphaned key instead of reporting a count.

## [v0.7.1] - 2026-08-18

Grok joins Claude and Codex as a third agent runtime, so a session can now run
on any of the three and still see the same tools, the same prompt layering and
the same interruption behaviour. Sessions also stop holding a runtime process
open forever while they sit idle, `duoduo upgrade` finally works when you run it
from inside a session, and the bundled Claude runtime is updated.

**Upgrading is routine this time** — reinstall and restart your channels as
usual. If you are on v0.7.0 and upgrade from inside a duoduo session, that now
works; before this release it could kill the very process performing the
upgrade.

### Highlights

- **Grok is a first-class runtime.** It sits behind the same seam as Claude and
  Codex rather than beside it: one long-lived agent process per session, duoduo's
  own tools reachable from it, mid-turn steering, and the same
  kind/instance/job/partition prompt fields — including whether the prompt is
  appended or replaces the runtime's own. Availability is checked against the
  Grok CLI you already have installed, and it fails closed: asking for Grok when
  Grok is not usable gives you a clear error, never a silent fall back to Claude.
  Token and cache accounting understands Grok's own reporting shape, so cost
  numbers stay comparable across the three.
- **Idle sessions release their runtime process.** A session that has gone quiet
  now tears down its runtime subprocess and rebuilds it on the next message,
  instead of holding it open for as long as a gateway stayed connected. This was
  unbounded before: a channel that keeps one permanent connection per binding —
  which is normal — kept every session it had ever touched resident, with no cap
  on how many or for how long. Nothing was gained by holding them; the model
  provider's prompt cache has already expired by then, so the only cost of
  reclaiming is a slightly slower first reply after a long silence.
- **`duoduo upgrade` survives being run from inside a session.** It now hands
  the work to a detached process, so the upgrade cannot be killed by the restart
  it is performing.
- **Codex tools stay where the model can see them.** duoduo's tools are mounted
  under their own namespace and pinned to the top level, so they no longer get
  demoted out of the model's directly-visible tool list on runtimes that hide
  ordinary tools behind a code-execution shim. Existing Codex conversations keep
  their old tool list until you start a new one.
- **Subconscious memory got more precise.** Crystallised claims are scoped to the
  entity they are about rather than to the whole corpus, and partition inboxes
  now have defined snapshot semantics, so a partition can no longer quietly lose
  or re-process work handed to it.

### Fixes

- The Feishu setup card dropped runtimes the daemon had advertised, so a runtime
  you had available could not be chosen during setup.
- A failed Grok availability probe reported "not authenticated" regardless of
  the real cause, sending people to re-login for problems that were not login
  problems.
- Codex sessions forked their conversation when only the shared board had
  changed, losing history for a change that did not require it.
- The Codex tool-call convention is no longer assumed, so reminders reach the
  model whichever calling convention it uses.
- Several idle-reclaim edge cases: reclaiming the Grok adapter on timeout,
  guarding the exit-path audit on a process that is actually alive, and covering
  the cold respawn.

### Preview — ambient

**duoduo is growing ears and a voice.**

A small device on the shelf. Always on, always listening, no wake word to
chant, no button to hold, no phone in your hand. It works out for itself when
something was meant for it — and most of the time, correctly, that answer is
"not this". You just talk in your room, and sometimes the room talks back.

It is running today. Here is what already works end to end, and what we are
proudest of:

- **Interrupt it. Actually interrupt it.** Not "it finishes the sentence then
  stops" — it cuts mid-word, and here is the part we like: it then knows exactly
  how much of its answer reached your ears and how much died in its throat. The
  next thing it says is grounded in what you *heard*, not in the paragraph it
  meant to say. And it never mutes its own microphone to hear itself think —
  going deaf the moment you open your mouth is not a conversation, it is a
  walkie-talkie.
- **It knows who is talking — and it will not guess.** An unfamiliar voice gets
  a temporary badge for that room, never a permanent name. You promote it by
  writing one line in the room's notes, the way you would introduce a person.
  The code is forbidden from deciding two voices are the same person on its own.
  We let it try that. Twice. Both times the entire room quietly collapsed into
  one identity — the most confident, least detectable kind of wrong.
- **It hears everything and answers almost nothing.** That restraint is the hard
  part, and it is where most of our measurement has gone. A machine that
  answers every sentence in a room is not present; it is a hazard.

The brains sit next to the models — continuous transcription, separating who
said what, understanding, speech — with the duoduo you already know doing the
thinking.

No install this time. Watch this space.

## [v0.7.0] - 2026-08-05

The daemon no longer accepts full control over a network port. Everything that
can change your agent's state now travels over a unix socket that only your own
user account can open, and the TCP port keeps serving the dashboard as a
read-only view. This release also adds per-model context windows and endpoint
routing, teaches `duoduo upgrade` to upgrade channel plugins too, and fixes
attachments arriving one message late. Bundled Claude runtime updated.

**Upgrading: reinstall and restart your channels.** The gateways connect to the
daemon over the new socket, so a gateway still running the old build cannot
reach the upgraded daemon — your bot will go quiet while accepting messages.
After upgrading, run `duoduo channel <kind> install`, then `stop` and `start`,
for each channel you use. From this release onward `duoduo upgrade` does this
for you; it cannot help the upgrade that introduces it.

### Breaking changes

- **The daemon's control interface moved to a unix socket.** It used to serve
  its entire interface — send messages, change models, archive sessions, read
  conversation history — on `127.0.0.1:20233` with no authentication of any
  kind. Any program on the machine could drive your agent, and any web page you
  visited could try. That interface now lives on a socket file that carries
  owner-only permissions, so the operating system enforces what nothing was
  enforcing before. The CLI and the channel gateways move over automatically.
- **`127.0.0.1:20233` is now read-only.** It answers the handful of methods the
  dashboard needs and rejects everything else, and it no longer speaks
  WebSocket. The dashboard is unaffected. Anything else pointed at that port
  gets a reply explaining where the full interface went. If your own scripts
  used that port for control, point them at the CLI instead — and note that
  when a locally-configured URL names this port, the CLI now recognises it as
  the old default and quietly uses the socket, so most setups keep working.
- **`ALADUO_DAEMON_HOST` means something different.** It used to choose where
  the main port bound, and setting it to a non-loopback address silently
  published that unauthenticated interface to the network. The read-only port
  is now pinned to loopback and ignores it. The variable instead selects the
  bind address for the optional remote listener described below, which refuses
  to start without a token.

### Highlights

- **Opt-in remote access, with a token.** If you genuinely need to reach a
  daemon from another machine, `duoduo daemon token new` generates a bearer
  token and stores it with owner-only permissions. The remote listener starts
  only when a host, a port and a token are all present, and every request must
  carry the token. A misconfigured remote setup — a public address with no
  token, or a port colliding with the read-only one — refuses to start rather
  than exposing anything.
- **`duoduo upgrade` upgrades channel plugins too.** It used to upgrade only
  the core, leaving gateways on older builds until you remembered to reinstall
  them by hand. It now installs each channel, restarts the daemon, and brings
  the channels back, in an order where a failed download leaves that channel
  running its previous build rather than stopping it. It also compares versions
  properly, so a pre-release is no longer mistaken for newer than its release.
- **Per-model context windows and endpoint routing.** A model served through a
  gateway can now declare its real context window, its own endpoint and
  credential, and tier aliases, so a session on that model is no longer capped
  by whatever window the runtime assumed. A model chosen by your settings
  rather than by an explicit `/model` gets its configuration attached too. See
  the `duoduo-runtime-admin` skill. Claude sessions only.
- **`/loop` follows a quality-graded work discipline.** The self-continuation
  loop now judges progress by whether a named gap actually closed, and stops
  when the work meets its bar instead of when it runs out of turns.
- **Codex sessions accept inbound images** as first-class turn input rather
  than as a path the model has to open for itself.
- **An agent must now say why it restarted the daemon.** v0.6.2 warned that
  the next release would reject a reason-less restart from inside a session;
  this is that release. It applies only to a restart run from within a
  session — you, your scripts and the menubar app are unaffected. The reason
  is the only way a session whose turn was killed can learn what happened;
  without one its likeliest conclusion is that a person interrupted it, which
  it will then state as fact.

### Fixes

- **Attachments no longer arrive one message late.** A file produced while a
  turn was settling was held back and delivered with the *next* message, so a
  background job's report would announce a chart that showed up minutes later,
  attached to something unrelated.
- **Repeating a gateway command works.** Sending the same command twice — the
  common case being `/model` to check the current model and then again to
  switch — silently swallowed the second one, which read as the agent hanging.
- **The daemon defends against hostile web pages.** A page you visit could ask
  your browser to talk to the daemon by pretending a public hostname resolves
  to your machine. Requests are now checked against that, in addition to the
  socket move that takes the control interface off the browser's reach
  entirely.
- **Uploads are written atomically**, so a file being received can no longer be
  read half-written, and a crafted filename can no longer escape the directory
  it belongs in.
- **Security advisories cleared.** Sixteen known vulnerabilities in bundled
  dependencies (eight high severity) are resolved.

## [v0.6.2] - 2026-07-28

This release stops background workers from being killed as collateral when an
agent declines to reply, makes daemon restarts explain themselves to the
sessions they interrupt, and fixes `duoduo upgrade` installing to the wrong
place on hosts where duoduo does not live in npm's default global prefix.
Bundled Claude runtime updated.

### Fixes

- **Background workers survive a skipped reply.** When an agent decided a
  message needed no answer, the mechanism that ended the turn also tore down
  every background task started during it. Because the underlying runtime
  reports such a teardown as "stopped by the user", the agent would then state
  as fact that a person had interrupted it — nobody had. Ending a turn no
  longer cancels the work started within it, a subagent declining to reply no
  longer silences its parent's answer, and a skipped first turn no longer
  blanks a later deliverable on scheduled runs.
- **`duoduo upgrade` installs where duoduo actually lives.** It used to run a
  plain global install, so on a host whose duoduo was installed outside npm's
  default global prefix — which is how the macOS menubar app installs it — the
  upgrade wrote a second copy elsewhere, left the running binary untouched,
  restarted the old daemon and reported success. It now resolves the prefix
  from the binary that is running, and uses the npm belonging to the Node.js
  that is running it, so it also works where `node` is not on `PATH`.
- **`duoduo upgrade` explains and verifies its restart.** The restart it
  performs now carries the version it resolved as the reason, so sessions it
  interrupts learn an upgrade happened instead of concluding a person
  interrupted them, and it accepts `--wake <session-or-alias>` for a session
  that was waiting on an answer. It also waits for the new daemon to pass a
  health check rather than assuming it booted, while correctly distinguishing
  "still starting" from "failed to start" on slower hosts.
- **One malformed job file no longer hides every other job.** A job whose file
  could not be parsed made the whole job list come back empty.
- **The `Notify` tool accepts display-name aliases**, which its description
  had advertised while only the CLI implemented it. Archived sessions are
  excluded from alias resolution — a stale identifier used to be accepted and
  reported as delivered into an inbox nobody drains.

### Highlights

- **`duoduo daemon restart` takes a reason, and can wake what it interrupted.**
  `-r "<what changed>"` reaches every session that wakes after the restart;
  `--wake <session-or-alias>` (repeatable) notifies a specific session that was
  mid-conversation, which otherwise waits silently for the next inbound
  message. Agents restarting the daemon from inside a session are warned when
  they omit a reason.
- **Job files can configure the SDK.** A job's frontmatter now accepts
  `prompt_mode`, `allowedTools`, `disallowedTools`, `additionalDirectories`
  and a nested `claude: { tools }`, with host-wide defaults in
  `kernel/config/job.md`. See the `duoduo-pipeline` skill.

### Dependencies and security

- **Bundled Claude runtime updated** to Agent SDK 0.3.220 (Claude Code
  v2.1.220), pinned to an exact version.
- **Transitive advisory patched** for `find-my-way` (HTTP/2 denial of service,
  reached through Fastify). Not reachable as duoduo ships — the daemon does not
  enable HTTP/2 and binds loopback by default — but pinned because the second
  condition is a setting an operator can change. The release dependency tree
  audits with zero known advisories.

### Note for skill users

The agent skills published from this repository are **not** part of the npm
package, so neither `npm install -g` nor `duoduo upgrade` updates them. After
upgrading, refresh them separately:

```bash
npx -y skills add https://github.com/openduo/duoduo --global --all
```

## [v0.6.1] - 2026-07-22

This patch release fixes two long-running conversation stalls, makes
background-worker completion delivery single-owner, validates scheduled jobs
before they are persisted, and updates the bundled Claude runtime plus
transitive security fixes.

### Fixes

- **Busy conversations no longer wedge after a mid-turn message.** duoduo now
  admits only one conversational turn at a time and routes later input through
  an explicit steering lane, so a message folded into an active Claude turn
  cannot leave the session permanently busy with no reply.
- **Background Agent completion has one conversation owner.** Claude's native
  completion continuation is now the only path that speaks into the
  conversation. duoduo records the lifecycle event durably without creating a
  duplicate callback turn, avoiding duplicate answers and subprocess restarts
  that could interrupt sibling workers.
- **Scheduled jobs fail loudly instead of silently never firing.** `@in` and
  `@every` now accept composite durations such as `2h30m` and `1d6h4m`.
  Invalid cron strings, malformed durations, and delays outside the
  representable time range are rejected when the job is created.

### Dependencies and security

- **Bundled Claude runtime updated** to Agent SDK 0.3.217 (Claude Code
  v2.1.217), pinned to an exact version. The upstream fix restores reliable
  completion notifications for multiple concurrent background Bash tasks, so
  duoduo's temporary Bash-to-Agent redirect has been removed.
- **Transitive dependency advisories patched** for Hono's Node server,
  `body-parser`, `brace-expansion`, `fast-uri`, and `protobufjs`. The release
  dependency tree audits with zero known advisories.

### Project

- Added OpenDuo editorial illustration assets.

## [v0.6.0] - 2026-07-15

duoduo now runs in one place — on your machine, as a host daemon. The
never-deployed container runtime is gone, along with the `/cd` command. This
release also adds a per-session reasoning-effort switch, closes a Feishu
secret-logging leak, and hardens background-task notifications, session
archiving, and outbox ordering. Bundled Claude runtime updated.

### Breaking changes

- **Container mode is removed.** The daemon runs only in host mode now. The
  `duoduo container` subcommand, the container onboarding branch, and all
  container-mode infrastructure are gone; onboarding no longer asks which
  runtime mode to use. If you onboarded before v0.6, nothing changes — you
  were already on the host daemon. Fresh installs go straight to host setup.
- **The `/cd` command is removed.** The in-session workspace-navigation
  command no longer exists. A session's working directory is fixed when the
  session is created; start a new session in the directory you want instead.

### Highlights

- **`/effort` — per-session reasoning-effort switch.** Set how hard the model
  thinks for a conversation without changing the model: send `/effort high`
  (or `low` / `medium` / `max`) in any session. Applies live to an active
  session and persists for future turns. See the `duoduo-runtime-admin` skill.

### Fixes

- **Feishu no longer writes the app secret to its log.** The Lark SDK was
  logging the configured `App Secret` in plaintext to the channel plugin log;
  it is now suppressed. If your Feishu plugin logs predate v0.6, rotate the
  secret and prune the old logs.
- **Feishu "read but no reply" is fixed.** When finalizing a streaming card
  failed, the error was swallowed and the reply never arrived until a
  restart. The failure now propagates so the static-message fallback fires
  and the user still gets the answer.
- **Background-task and worker completion notifications are scoped
  correctly.** A long-running command promoted to the background, or a
  finished subagent, no longer floods the top-level conversation with
  bookkeeping turns or double-posts the same completion. Notification
  guidance also stops the model from silently skipping a reply it hasn't
  actually delivered.
- **Session archiving is safer.** Archiving now refuses unless the session is
  provably empty of pending work (checking every shape of in-flight work),
  ignores channel placeholder actors, and treats the archive marker as a real
  "about to disappear" signal.
- **Outbound delivery preserves emit order.** The per-session outbox is now
  drained one record at a time and serialized, so a channel socket sees
  replies in the order they were produced.
- **Drain errors surface immediately** instead of being stranded until the
  next tick.

### Dependencies

- **Bundled Claude runtime updated** to Agent SDK 0.3.210 (Claude Code
  v2.1.210), pinned to an exact version.

## [v0.5.10] - 2026-07-09

This release adds idle auto-compact for channel sessions, switches the
built-in tool surface from a denylist to an allowlist, and fixes a Feishu
card-anchoring bug plus a background-turn double-reply. Bundled Claude
runtime updated.

### Highlights

- **Idle auto-compact for channel sessions**. A channel session that has sat
  idle past a configurable threshold and grown past a token floor now
  silently runs `/compact` on its next turn — no manual `/compact`, no
  surprise cost spike from a stale prompt cache. Off by default everywhere;
  enable and tune per conversation with `duoduo session config <session>
  set auto_compact_idle_minutes=50 auto_compact_min_context_tokens=100000`.
  A one-line notice on the session's next reply reports what was compacted
  and its measured stats, so retuning is based on real numbers rather than
  guesswork. See the `smart-compaction` skill for the full knob reference
  and break-even formula.
- **Built-in tool surface is now an allowlist, not a denylist**. Previously
  every session got the SDK's full built-in tool set minus whatever a
  `disallowedTools` entry blocked. As of v0.5.10, sessions get a fixed core
  set (`Bash`, `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Agent`, `TaskOutput`,
  `TaskStop`, `Skill`, `ToolSearch`, `TaskCreate`, `TaskGet`, `TaskUpdate`,
  `TaskList`, `SendMessage`); anything else (`WebSearch`, `WebFetch`,
  `TodoWrite`, `Workflow`, `Monitor`, `Cron*`, …) is off unless explicitly
  added via a new nested `claude.tools` key in a channel's kind or instance
  descriptor. **Action needed if you rely on tools outside the core list**:
  add them under `claude.tools` — see the `duoduo-channel-admin` skill's
  upgrade note for the exact migration recipe. `disallowedTools` entries
  naming built-in tools are now no-ops (MCP tool names still work); a
  startup warning flags any descriptor still relying on the old behavior.

### Fixes

- **Feishu group replies no longer attach to the wrong message**. When
  someone interjected mid-turn in a busy group chat, the agent's streaming
  card reply could anchor to — and appear to answer — the wrong message.
  Card anchoring is now pinned per-turn to the event it's actually
  answering.
- **A background job or subconscious result could double-post a reply**. A
  race between an admitted turn and a same-session background notification
  could cause the turn's prompt to be re-queued and answered twice. Fixed by
  excluding not-yet-settled admitted prompts from being re-selected by a
  re-iterated mailbox drain.
- **Claude/Sonnet thinking quality restored on streaming sessions**. A
  leftover compatibility flag was force-disabling extended thinking on every
  streaming Claude turn; removed, so streaming sessions think as well as
  non-streaming ones again.
- Admitted-turn outbound attachments (images, files) are now delivered
  instead of silently dropped.
- Closed a rare TOCTOU window where archiving a session concurrently with a
  runtime-state write could corrupt session state.

### Dependencies

- **Bundled Claude runtime updated** to Agent SDK 0.3.205 (Claude Code
  v2.1.205).

## [v0.5.9] - 2026-07-01

A patch release updating the bundled Claude runtime, which brings the latest
models to the `/model` menu.

### Changes

- **Bundled Claude runtime updated** to Agent SDK 0.3.197 (Claude Code v2.1.197).
- **Latest models available via `/model`**. The new runtime surfaces newer models
  (including Claude Sonnet 5) in the endpoint model list. Because model selection
  is fully dynamic — the `/model` menu comes from the live endpoint and any model
  id is passed through verbatim — new models are usable immediately with no
  configuration change: `/model claude-sonnet-5`, or set a per-job `model` field.

## [v0.5.8] - 2026-06-30

This release makes mid-turn steering land faster and more reliably across both
Claude and Codex runtimes, reworks background memory consolidation to run within
a bounded time budget, adds a `duoduo session compact` command, and updates the
bundled Claude runtime plus a security patch.

### Highlights

- **Mid-turn steering reaches the agent at the next tool boundary**. When you
  send a follow-up message while the agent is already working, it is now picked
  up at the next tool boundary instead of waiting for the whole turn to finish —
  on both Claude and Codex runtimes. A completed background task can likewise
  surface its result mid-turn rather than only after the turn ends.
- **`duoduo session compact` — compact a channel session's context on demand**.
  Queue a `/compact` for any channel session by key or name; it runs on that
  session's next turn and the acknowledgement lands in the target session's
  outbox. Useful for trimming a long-lived session's context before it hits its
  own auto-compact threshold. Channel sessions only.
- **Background memory consolidation now runs on a bounded time budget**. The
  memory-weaver's nightly consolidation previously self-selected an unbounded
  scan that could time out producing nothing. It now works one bounded day at a
  time, picked by a program-computed gap check (`duoduo memory check` reports the
  chosen gap), so each pass converges instead of stalling.

### Changes

- **Recurring follow-up messages no longer silently dropped**. Fixed a case
  where a re-queued message could be lost when a stale watermark made the system
  treat it as already handled.
- **`duoduo` CLI surfaced as the runtime command center** in the agent's own
  context, with `--help` output corrected.
- **`vote` skill added** — a multi-perspective, clean-context adversarial
  decision panel for high-stakes judgments, written to be host-neutral and
  usable by any agent.
- **Background continuations no longer break in-process tools**. Holding the
  input stream open across background-subagent continuations stops job and
  subconscious turns from hitting a "Stream closed" error.

### Security

- **Bundled Claude runtime updated** to Agent SDK 0.3.196 — includes an upstream
  fix that prevents duplicate tool results in long-running streaming sessions.
- **Patched js-yaml advisory** (GHSA-h67p-54hq-rp68, denial-of-service via
  repeated YAML merge-key aliases) on both transitive paths via pinned overrides.

## [v0.5.7] - 2026-06-23

A maintenance release: a streaming-stability fix that stops background work
from being lost, the `/loop` mechanism generalized into a reusable named-prompt
registry, Codex image-generation delivery fixes, security patches, and the
bundled Claude runtime updated.

### Fixes

- **Background subagents no longer killed by a self-notification**. When a
  background task finished while a channel session was idle, its completion
  notification could trigger an unnecessary restart of the session's runtime —
  silently killing any other background tasks still running. These now reuse the
  live runtime instead of restarting, so concurrent background work survives.
- **Codex image generation delivered reliably (Codex 0.140+)**. Generated images
  produced by Codex were sometimes silently dropped; they are now delivered
  correctly, including the newer inline-image result shape.
- **Inbound work no longer stalls on a dropped notification**. Fixed a case
  where a never-admitted background result could leave a session's processing
  loop parked until its next scheduled wake.
- **Subagent narration no longer leaks into channel cards**. Internal subagent
  streaming output is now marked as a side channel and dropped by channels
  rather than rendered into the main reply.
- **Picture-form heading match is case-insensitive** (memory maintenance).

### Changes

- **`/loop` generalized into a named-prompt-injection registry**. The recurring
  `/loop` capability is now one entry in a general mechanism for named prompt
  injections, with a self-describing `duoduo prompts` CLI to list what's
  available. Adding a second named prompt no longer requires touching the core
  prompt path.
- **Bundled Claude runtime updated** to a newer Agent SDK build.

### Security

- Patched transitive dependency advisories (form-data, hono, protobufjs) via
  pinned overrides.

### Diagnostics

- Added structured logging when a Feishu streaming card fails to close, to aid
  diagnosis of the "read-but-no-reply-until-restart" symptom.

## [v0.5.6] - 2026-06-16

This release ships `/model` session-level model switching, `/loop` as a
first-class recurring-task primitive, a cross-runtime usage footer, Skip
lifecycle hardening, and dependency updates (SDK 0.3.178).

### Highlights

- **`/model` — session-level model switching (Claude, experimental)**. Type
  `/model` to list available models, `/model <id>` to switch the running
  session, `/model reset` to restore the daemon default. On Claude sessions
  the change takes effect on the next turn; on Codex sessions it is applied
  at the next thread fork. Unknown model ids return an error rather than
  silently accepting the request.
- **`/loop` — runtime-agnostic recurring tasks**. Kick off a self-pacing
  loop with `/loop <task>`. The loop runs as a job, paces itself via
  `ScheduleWakeup`, and carries a concrete acceptance rubric so each
  iteration can verify its own progress. Per-job model override is
  supported; gateway injection means `/loop` works from any channel without
  special channel code. Full rubric/verify/deliver-with-gaps discipline is
  documented in the `duoduo-loop` skill.
- **Cross-runtime usage footer**. Every finalized turn now appends a
  one-line footer: `↑ in · cache% · ↓ out · $cost` for Claude turns, step
  count for Codex turns. The footer also shows which model was actually
  billed (served model may differ from the requested model). The footer
  reflects per-turn deltas, not process-global accumulators.
- **Footer: context occupancy segment**. The footer now includes an absolute
  context-token count (`ctx Nk`) so you can see how full the context window
  is without leaving the chat.
- **Memory partition consumer-contract gate**. Each subconscious partition
  declares which `.pending` signal kinds it consumes in its `contract:`
  frontmatter. The memory-check delivery layer validates the declaration
  before posting — an undeclared signal kind is withheld, so stale or
  mismatched signals never land in the wrong partition inbox. Upgrading the
  subconscious partition prompts to v0.5.6 activates the gate.

### Fixes

- **Skip lifecycle hardened**. A `Skip` decision now terminates the
  streaming turn, silences all egress (including partial card updates), and
  delivers any already-admitted turn content. The skip-rewind injection only
  fires on genuine human turns, not on periodic cadence pings.
- **Footer: per-turn cost delta**. Claude streaming sessions now report the
  per-turn cost delta rather than the process-global cost accumulator,
  fixing inflated cost figures on long-lived sessions.
- **Daemon async fault isolation**. Unhandled async errors in one RPC
  handler no longer crash the daemon process.
- **`/model` validation is soft**. Passing an unrecognised model id now
  returns a human-readable Markdown error instead of a bare JSON rejection.

### Dependencies

- `@anthropic-ai/claude-agent-sdk` 0.3.170 → 0.3.178
- `esbuild` updated; `pnpm` overrides migrated to new format

## [v0.5.5] - 2026-06-09

This release adds an opt-in Feishu card footer that surfaces each turn's
cost/effort, makes a reset session aware that it was reset, and ships the
first mechanical memory-maintenance lints. It also fixes a `/compact` gap on
Claude streaming sessions and several Feishu setup-card regressions.

### Highlights

- **Feishu card footer (experiment, default off)**. Set
  `ALADUO_EXP_FEISHU_CARD_FOOTER=1` to add a one-line ops footer to the
  finalized streaming card: `elapsed · ↑in ↓out · cost` on a Claude turn, or
  `elapsed · N steps` on a Codex turn (Codex token counts are
  thread-cumulative and it reports no cost, so the step count is the only
  honest per-turn figure). The flag is read by the Feishu channel process —
  restart the channel, not just the daemon, after setting it.
- **Reset sessions know they were reset**. After `/clear` (or its `/reset`
  alias), the fresh agent session's first turn now carries a one-time notice:
  start fresh, do not resume the prior session's pending work, and the
  previous session id is retained so the new session can look up the prior
  history if the user recalls something from before the reset. The notice is
  runtime-neutral.
- **`/compact` fixed on Claude streaming sessions**. Previously `/compact`
  compacted the on-disk history while the live streaming subprocess kept the
  full in-memory prefix, so the token count never dropped and a long session
  could still hit `too_many_total_tokens`. The compact is now routed in-band
  on the live subprocess.
- **Mechanical memory maintenance (experiment, default off)**. A new
  cadence-driven memory lint measures the memory tree and routes convergence
  signals to the subconscious partitions. `ALADUO_EXP_MEMORY_CHECK=1` enables
  the measure-and-notify lints; `ALADUO_EXP_MEMORY_FORGET=1` additionally lets
  it remove long-stale, board-unreachable orphan nodes (git-recoverable).
  **Refresh this host's subconscious partitions to v0.5.5 before enabling
  these** — the lint's signals are version-coupled to the partition prompts
  that consume them.
- **`daemon status` shows more**. `duoduo daemon status` now reports the
  cadence heartbeat (last tick / interval), subconscious round progress, and
  the memory-check experiment-flag state — the reliable way to confirm an
  experiment flag took effect, since the background daemon's env is not
  visible via `ps`.

### Feishu setup fixes

- First-time **group** setup cards now show and pre-select the workspace-root
  (⌂) option, so a group whose workspace has no discovered sub-projects no
  longer dead-ends with an empty project dropdown.
- The setup card's project dropdown uses the correct default-selection field,
  fixing a regression where the pre-selected project was rejected.
- Forwarding an interactive card to the bot now renders the real content
  instead of an `[interactive]` placeholder.

### Other fixes

- A `workspace` job whose directory or `CLAUDE.md` is removed after creation
  now fails the run explicitly instead of running silently with empty context.
- Skip-rewind notices only inject on a genuine human turn, so periodic empty
  runs no longer re-state the prior skip reason every tick.
- Parallel worker-completion notifications are coalesced into one turn.

## [v0.5.4] - 2026-06-02

This release makes the `duoduo` CLI a first-class surface for both human
operators and agents: sessions can be named, listed, and woken by name;
the CLI's output and install paths are hardened now that an agent may run
`duoduo …` itself. It also stops recurring background jobs from growing an
unbounded conversation thread, refreshes the shipped subconscious prompts,
and includes runtime-robustness and dependency updates.

### Highlights

- **`duoduo session` command**. A new CLI surface to manage sessions:
  - `duoduo session list [--kind …] [--named] [--all] [--json]` — the live
    route table of every session the daemon knows.
  - `duoduo session alias <key> "<name>"` — give a session a human label so
    it is legible in `list` and usable as a wake target.
  - `duoduo session notify <target> -m "<msg>"` — wake another session by
    key or alias with a source-tagged notification (for cross-session
    orchestration). Only foreground/job sessions are valid targets; the
    kernel/subconscious plane is isolated and refused.
  - `duoduo session archive <key>` — move (never delete) a session's
    artifacts.
- **`session list` hides orphan job sessions by default**. A `job:` session
  whose owning job is no longer in the active set (e.g. a job recreated with
  a changed schedule/workspace, or one whose definition was deleted) is now
  hidden by default so the listing agrees with the job list. Pass `--all`
  (alias `--include-orphans`) to surface them, marked `(orphan)`.
- **Recurring jobs can opt out of thread reuse (`stateless`)**. A periodic
  job that does not depend on prior-run state can set `stateless: true` so
  each run starts a fresh thread instead of resuming (and growing) one
  long-lived conversation. Stateless runs receive an explicit contract:
  state is not retained, any dependency must be persisted, and the run must
  end with an acceptance rubric. `ManageJob` also always exposes the
  effective `runtime` field. (`stateless` is rejected on keepalive jobs,
  whose whole point is a persistent lifecycle.)
- **CLI output and install hardening**. Now that an agent may invoke the CLI
  directly: absolute home paths are collapsed to `~` in command output;
  `duoduo daemon logs` tails the last lines by default (`--lines N` / `--all`
  to override); installing a channel plugin from a local `.tgz` requires the
  explicit `--from-path` flag (npm-package installs are unchanged); container
  lifecycle commands are removed from the default agent-facing help; and
  interactive-only commands fail fast with an actionable message under a
  non-interactive (non-TTY) invocation instead of hanging.
- **Degraded-but-healthy startup when a runtime is missing**. If the native
  Claude runtime binary is unavailable (e.g. an optional dependency failed to
  install), the daemon now boots healthy and surfaces a per-session
  "runtime unavailable" error instead of failing silently.
- **More reliable background-job autocompaction**. A recurring Codex job no
  longer mishandles a turn-terminal notification, which previously could let
  a job thread grow until it repeatedly hit compaction.
- **Deterministic mailbox ordering**. Mailbox items that arrive within the
  same millisecond now drain in a deterministic FIFO order.
- **Subconscious prompts refreshed**. The shipped active-partition prompts
  are updated: the recurring-pattern concept is reframed into distinct
  "lesson" and "groove" nodes, the intuition board is no longer autoloaded
  as a partition gradient, and the entity/effectiveness crystallizer is
  scoped more tightly.

### Package versions

- `@openduo/duoduo` → 0.5.4
- `@openduo/protocol` → 0.5.4
- `@openduo/channel-feishu` → 0.5.4
- `@openduo/channel-acp` → 0.5.4

### Migration

For most operators, upgrade the package and restart the daemon:

```bash
npm install -g @openduo/duoduo@0.5.4
duoduo daemon restart
```

If you previously installed a channel plugin from a local tarball, note that
this now requires `duoduo channel install --from-path <file.tgz>`; installing
by npm package name is unchanged.

Subconscious prompts are still not auto-upgraded. To adopt the v0.5.4
partition prompts, use the `subconscious-refresh` procedure from the
`duoduo-runtime-admin` skill and review the diff before applying it.

### Verification

The release was validated with lint, typecheck, the full local test suite
(2821 passing), meta-prompt lint, release build/pack dry-run, and the three
required Linux distribution fixtures: `claude-auth`, `api-key-only`, and
`omit-optional`.

## [v0.5.3] - 2026-05-25

This release promotes Codex from a narrow backend option to a peer
runtime choice beside Claude, refreshes the shipped subconscious
prompts, and tightens the stdio terminal experience. It also includes
dependency/security updates and release-verification fixes.

### Highlights

- **Claude and Codex are peer runtime choices**. Hosts can expose
  whichever runtimes are actually installed and authenticated. Claude
  remains the conservative fallback, while Codex can be selected per
  channel, per job, or globally with `ALADUO_DEFAULT_RUNTIME=codex`.
- **Feishu setup reflects available runtimes**. Setup cards only show
  runtime choices the daemon can actually run. If Codex is installed or
  logged in after the daemon is already running, restart the daemon so
  availability is re-probed.
- **Stdio output is cleaner**. Assistant text is buffered more cleanly
  around status and tool output, reducing visible interleaving in the
  terminal UI.
- **Runtime shutdown and packaging are more reliable**. The bundled
  Claude Agent SDK dependency is updated to the 0.3 line, the Codex
  runtime path now cleans up its helper process more reliably, and the
  release verifier works on macOS's default Bash.
- **Subconscious prompts refreshed**. The v0.5.3 public tag carries
  updated active partition prompts for recall discipline, evidence
  discipline, and recurring-pattern convergence. The retired
  `opportunity-scout` and `working-memory` prompts are no longer part
  of the published subconscious tree.

### Package versions

- `@openduo/duoduo` → 0.5.3
- `@openduo/protocol` → 0.5.3
- `@openduo/channel-feishu` → 0.5.3
- `@openduo/channel-acp` → 0.5.3

### Migration

For most operators, upgrade the package and restart the daemon:

```bash
npm install -g @openduo/duoduo@0.5.3
duoduo daemon restart
```

If you want Codex routing, install and authenticate the Codex CLI on
the host, then restart the daemon. Existing live conversations do not
hot-swap runtime just because a default changed; rebind or archive a
session when you want a clean switch.

Subconscious prompts are still not auto-upgraded. To adopt the v0.5.3
partition prompts, use the `subconscious-refresh` procedure from the
`duoduo-runtime-admin` skill and review the diff before applying it.

### Verification

The release was validated with lint, typecheck, the full local test
suite, meta-prompt lint, release build/pack dry-run, and the three
required Linux distribution fixtures: `claude-auth`, `api-key-only`,
and `omit-optional`.

## [v0.5.2] - 2026-05-16

This release teaches the foreground agent how to use its own memory
graph, lands cross-runtime `/compact` and `/undo`, and retires two
subconscious partitions that were producing files no one was reading.

### Highlights

- **GraphSkill consumer contract**: the meta-prompt now tells the
  agent how to navigate dossiers with `[[wikilinks]]`, how to read
  modal tags (`[observation]` / `[inference]` / `[instruction]` /
  `[conditional]` / `[hypothesis (unratified)]` / `[superseded]`),
  when to open a dossier before acting, and how the fragment loop
  keeps the graph from amplifying its own past.
- **`/compact` and `/undo` work everywhere**. Type them in any
  channel (Feishu DM, stdio, ACP editor). Both runtimes shrink the
  conversation in place or roll back the last `N` exchanges, with a
  text reply when the command finishes.
- **`@<file>` imports in `memory/CLAUDE.md` actually inline now**.
  The runtime parses Claude Code's `@<file>` directives itself and
  injects the rendered import graph into both Claude and Codex
  sessions through one path.
- **ACP editor sessions no longer race the first prompt**. The
  bridge keeps editor-side and daemon-side sessions in lockstep on
  open and close.
- **Two partitions retired**: `opportunity-scout` and
  `working-memory`. Their prompts stay as design archaeology and
  the meta-session scheduler auto-skips them.

### Package versions

- `@openduo/duoduo` → 0.5.2
- `@openduo/channel-acp` → 0.5.2 (session lifecycle fix)
- `@openduo/protocol` stays at 0.5.0 (no source changes)
- `@openduo/channel-feishu` stays at 0.5.1 (only transitive deps)

### Migration

For most operators a `duoduo daemon restart` after the upgrade is
enough. The new GraphSkill consumer contract and `@<file>`
resolution live in the npm package's `bootstrap/` and take effect
immediately.

If you want the partition retirement and the prompt tightening to
land in your kernel under `~/aladuo/subconscious/`, run the
`subconscious-refresh` procedure documented in the
`duoduo-runtime-admin` skill. Existing `memory/priority.md` files
stay on disk and are no longer rewritten; rename to
`priority.md.retired-YYYY-MM-DD` if you want it out of the way.

One subtle behavior change worth a glance: `@<file>` directives
inside `memory/CLAUDE.md` now actually inline their target. Before
v0.5.2 the directive was silently inert under
`additionalDirectories`, so anything referenced there did not
reach the system prompt. If you had directives that you assumed
were no-ops, review them.

### Skill refresh

The public skills under `duoduo-runtime-admin` and
`duoduo-channel-admin` have been refreshed to cover the new
`/compact` and `/undo` commands, the ACP lifecycle alignment, and
the post-v0.5.2 partition status. Load the matching skill on
demand — there is nothing to install.

## [v0.5.1] - 2026-05-06

Twelve commits since v0.5.0. The headline change is the silicon-being
identity rewrite of the meta-prompt (an emotional re-grounding, not a
behavioral change), paired with a generalization of the per-session
"mission fingerprint" guard to the full instructions surface (schema
v1 → v2, transparent migration). The release also lands user-visible
fixes for the Feishu voice-note path, Codex thread/fork on instruction
drift, and a clarification of the unconditional vs. agent-conditional
delivery semantics of the job framework's `notify` field. Subconscious
partition prompts have been retuned and a `memory/index.md` artifact
that no longer earned its keep has been retired in favor of wiki-style
`[[slug]]` links throughout.

No schema breakage that requires manual migration — the v2 instructions
fingerprint upgrade fires lazily on each session's next drain, and the
removal of `memory/index.md` is filesystem-level only (the runtime no
longer reads it; existing files become inert).

### Behavior changes

- **Meta-prompt: silicon-being identity + posture toward humans**
  (`45d09447`). The system prompt the runner appends to every session
  has been rewritten around the agent being a silicon being collaborating
  with humans, not a faceless assistant. This affects how the agent
  introduces itself, takes feedback, and maintains continuity across
  drains. Behavior contract is unchanged — same tools, same memory,
  same recall rules — but turn-level voice and self-awareness will
  feel different. Existing channels and jobs do not need any action.

- **Instructions fingerprint guard generalized to full surface
  (schema v1 → v2)** (`3c6618c8`). The per-session sticky-mission guard
  now fingerprints identity + kind prompt + instance prompt + memory
  board + mission, not just the mission. Any drift in any layer triggers
  a Codex thread fork (preserving conversation history) or a Claude
  reset. Migration is automatic on first drain after upgrade: state.json
  schema is bumped 1 → 2 atomically, the legacy `mission_fingerprint`
  field is cleared, and the new `instructions_fingerprint` is stamped.
  Hot-restart safe — sessions that were mid-drain when the daemon
  restarted resume cleanly on the new schema.

- **Codex thread/fork preserves history on instruction drift**
  (`8018bcf4`). Previously, when a Codex session's instructions changed
  mid-life, the runtime would fall back to `thread/start` and lose the
  prior conversation. The new behavior calls `thread/fork` from the
  parent rollout when one is available, which carries the full history
  forward into a fresh thread that honors the new base instructions.
  Falls back to `thread/start` if the parent rollout has been GC'd.

- **Job framework: `notify` field is unconditional, `Notify` tool is
  conditional** (`9271fd7d`). The `ManageJob` tool description and the
  `<job-status>` system-prompt guidance now clearly distinguish two
  delivery modes: filling the frontmatter `notify:` field triggers
  framework delivery on every completion (no matter what the job
  instruction says about exiting silently), while leaving it empty and
  having the job call the `Notify` tool from inside its instruction
  gives the agent per-run conditional delivery. The fallback guidance
  on `<job-status event="job.complete">` for channel-receiver +
  periodic-schedule jobs has been tightened to a binary "call Skip
  with a reason, or produce text only when the completion is
  meaningful" — explicitly forbidding self-notes like
  `"Skip — routine, no urgent."` that the agent was emitting as text
  instead of as a tool call.

### Fixes

- **Feishu: opus/ogg attachments now send as native voice notes**
  (`adfd3399`). When the agent calls `QueueOutboundAttachment` with an
  `.opus` or `.ogg` file, the gateway uploads it as a Feishu native
  audio bubble rather than a generic file attachment. Useful for
  generated voice replies and audio summaries. Other audio MIMEs
  (`audio/mpeg`, `audio/wav`) continue to ride the generic-file path.
  See `skills/duoduo-channel-admin/references/feishu.md` ("Outbound
  media rendering") for the full MIME → render mapping.

- **Persist `CLAUDE_CODE_EXECUTABLE` override across daemon restarts**
  (`6101a378`). When `duoduo onboard` runs with `CLAUDE_CODE_EXECUTABLE`
  set in the environment (e.g. pointing at an SDK-bundled `claude`
  binary on a host where the optional native dep didn't install), the
  override is now persisted into the host `.env` so the daemon picks
  it up on subsequent restarts. Previously this only worked while the
  shell that started the daemon was alive.

- **Codex foreground: register missing tools (`Skip`,
  `QueueOutboundAttachment`)** (`889e3e06`). A registration regression
  introduced on 2026-04-03 left these two tools missing from Codex
  foreground sessions; the bug only became user-visible on 2026-04-17
  when channel descriptors started actually promoting `actor.runtime`
  to "codex". For the gap window, every Codex-runtime channel session
  was missing silent-skip and arbitrary-file egress.

### Internal / not user-visible

- `feat(notify): add correlation labels` (`c997ff34`) — adds
  `correlation_id` / `reply_to` fields to the Notify MCP tool so async
  request↔reply pairs can be aligned in the SDK-resumed transcript.
- `subconscious: tune partition cadence` (`d44d30de`) — adjusts the
  per-partition `cooldown_ticks` in the playlist scheduler.
- `refactor(memory): retire memory/index.md, switch to wiki-style refs`
  (`26f0ae80`) — drops a legacy global-index file in favor of
  Obsidian-style `[[slug]]` references throughout entity / topic /
  CLAUDE.md files. Existing `memory/index.md` files become inert.
- `prompt: pink-elephant fixes for cadence-executor, memory-weaver,
  opportunity-scout, subconscious` (`87a4f132`) — removes literal
  template strings (e.g. `"Skip — ..."`, `"you might want to..."`)
  from subconscious partition prompts that were anchoring the agent
  on the wrong outputs.

## [v0.5.0] - 2026-04-30

First stable release of the v0.5 line. Promotes the rc.2.x series with
four small but operator-visible fixes on top of rc.2.1. No schema
breakage, no config migrations required — drop-in upgrade from rc.2.1.

The headline behavior changes are around two surfaces operators
interact with directly: the `duoduo channel install` contract, and
the dashboard `% cache` tile.

### Behavior changes

- **`duoduo channel install <tarball>` is now pure write-to-disk and
  no longer touches the running plugin** (`c3ce2a6c`). Install stages
  the new package alongside the running one and atomically renames it
  into place; POSIX file semantics keep the running process serving on
  its previous code until it exits on its own. The new code only
  takes effect after an explicit
  `duoduo channel <kind> stop && duoduo channel <kind> start`.
  Pre-v0.5 behavior killed the plugin process before replacing files
  and left it stopped — automation that relied on that side effect
  needs to issue an explicit stop+start now. The skill documentation
  has been updated to describe the new contract and the upgrade
  sequence.

- **Dashboard `% cache` is now a per-protocol blended rate that
  excludes drains it can't reliably classify** (`c42ab859`). The
  previous formula
  `cache_read / (cache_eligible_input_tokens + cache_read)` was wrong
  for both wire protocols we drive — Anthropic disjoint vs.
  OpenAI/Codex subset semantics — and produced a misleading number
  (50% on hosts that should have been 70%+). Each drain is now tagged
  with its protocol at the source, and the dashboard computes the
  hit rate per protocol and blends the two by token weight.
  Anthropic-compat backends that omit `cache_creation_input_tokens`
  (e.g. GLM via z.ai) cannot be classified by data shape alone and
  are deliberately excluded from the rate. Existing pre-fix drain
  records lack the protocol tag and are also excluded — so on first
  upgrade the tile shows `--` until tagged drains accumulate
  (typically minutes on an active host). This is the cutoff working
  as designed, not a bug.

### Fixes

- **stdio CLI: input bar no longer drifts to the middle of the
  screen on long turns** (`1c4f1449`). Multi-turn sessions where the
  agent streamed long markdown plus several tool calls would push
  Ink past its full-clear threshold, leaving the input bar stranded
  with ~50 blank rows below. The fix bounds the live region's
  source height: the streaming draft is rendered as a tail-window of
  the most-recent `terminal_rows - 6` lines (the full text still
  commits to scrollback at turn end), the live tool-call display
  collapses to the last 2 with a "+N earlier" indicator, and the
  outer Box has an explicit width so Yoga wraps long lines into
  the right number of `\n`. The Ctrl+B post-turn detail view stays
  full-list.

### Internal

- **Time annotations injected into `<time-context>`, `<job-tick>`,
  and `<skip-rewind>` prompt blocks now include a daemon wall-clock
  alongside the UTC timestamp on host-mode deployments**
  (`e9de06f2`). On host mode the daemon TZ is the operator TZ, so
  the agent gets a non-UTC reading of the same instant for
  scheduling and "what time is it" questions. In container mode the
  annotation is suppressed because the daemon TZ does not in
  general match the channel user's TZ. No operator-visible config
  surface — the host/container split is automatic.

- `@openduo/duoduo`, `@openduo/protocol`, `@openduo/channel-feishu`,
  `@openduo/channel-acp`: version bump to `0.5.0`. Distribution
  verification (`tests/distribution/linux/run-verification.sh`) green
  on all three fixtures (`claude-auth`, `api-key-only`,
  `omit-optional`).

## [v0.5.0-rc.2.1] - 2026-04-24

Patch release on top of rc.2. Fixes two channel-feishu bugs that could
leave a Feishu chat routing to the wrong session after a restart or a
transient disk failure. Core / protocol / channel-acp have no code
changes — the version number moved forward so CLI / Docker / npm are
consistent with the feishu fix.

Safe drop-in upgrade from rc.2.

### Fixes

- **channel-feishu: self-repair watched-sessions against the daemon
  descriptor on startup** (`75d6d16a`). A Feishu chat whose
  `watched-sessions.json` recorded a degraded session_key (one that
  had fallen back to `defaultWorkDir` instead of the /setup-bonded
  workspace) used to keep re-subscribing under that wrong key on every
  restart. The daemon then saw two parallel sessions for the same
  chat — one correct, one wrong — and future messages could land on
  either. The channel now calls `channel.describe` on startup for
  every watched key, rebuilds the canonical key from
  `descriptor.cwd`, rotates the binding, and rewrites the stores. On
  first inbound for a not-yet-hydrated chat the same describe happens
  before the lazy session_key init. Transient RPC hiccups stay
  retryable.
- **channel-feishu: cs-binding-store persist chain survives disk
  failures** (`6283c8e7`). A single `fs.writeFile` rejection inside
  `enqueuePersist()` left `persistChain` permanently rejected, so
  every subsequent `rememberBinding()` silently no-opped against
  disk while memory kept mutating. Only a process restart recovered.
  The stored chain now swaps in a `.catch()`-ed copy after each
  persist so the next write starts from a resolved baseline; the
  caller-facing promise still propagates the error so awaiters see
  the failure.

### Internal

- `@openduo/duoduo`, `@openduo/protocol`, `@openduo/channel-acp`:
  version-only bump (no code changes) so `duoduo --version`, Docker
  tag, and the npm `@next` pointer all read `0.5.0-rc.2.1` in lockstep
  with the feishu fix.

## [v0.5.0-rc.2] - 2026-04-24

Second release candidate of the v0.5 line. Concentrates on session-lifecycle
correctness (Phase 3 of the Registry → Derived View refactor), dashboard
signal fidelity, and subconscious cost reduction. No user-visible API
breakage since rc.1 — safe to upgrade.

### Fixes

- **Phase 3 legacy-registry sweep no longer resurrects archived sessions**:
  on first post-upgrade daemon start, the one-shot migration from
  `var/registry/sessions/` to `var/sessions/<hash>/state.json` used to
  backfill a fresh `state.json` for every registry row — including rows
  whose sessions had already been archived days earlier. The result was
  ghost sessions reappearing on the dashboard with stale metadata. The
  sweep now probes `var/sessions-archive/` and skips any entry whose
  archive already exists (bare ref or collision-suffixed variant), so
  the archive stays the terminal state.
- **Dashboard KV-cache-rate no longer diluted by cache-unaware drains**:
  the rate denominator used to sum `input_tokens` across all drains,
  including providers that don't report cache fields at all (some compat
  endpoints). Only drains that report a cache field (as a number —
  including a legitimate 0) now contribute to the denominator.
- **`session.archive` drops stale in-memory index entries even when disk
  artifacts are already gone**: the `not_found` branch now calls
  `SessionIndex.remove()` so dashboard stops reporting a session whose
  live dir was removed out-of-band.
- **Concurrent `channel.ack` during archive refused at entry**: prevents
  delivery-cursor writers from creating files beside a just-renamed
  session dir; observer re-read is now wrapped in the per-session state
  lock and re-checks the archiving marker after the lock is taken.
- **All session-dir writers consolidated on one per-session mutex**:
  `ensureSessionDescriptor`, `writeSessionMeta`, `updateSessionRuntimeState`,
  and `enqueueMailboxItem` now take the same lock that `archiveSessionDir`
  takes. Closes the last class of "writer survives past archive's
  liveness check and writes into a just-renamed path" races.
- **Cadence scheduler skips due jobs whose session is being archived**:
  prevents a cron firing concurrent with an in-flight `session.archive`
  from spawning a new session under the same key while the archive
  rename is mid-flight.
- **`ManageSession(show)` is strictly read-only**: no longer materializes
  a state.json just because the caller asked for info.
- **`discoverChannelId` prefers the newest archive during retry**:
  partial-archive retries now resolve the owning channel from the
  freshest archived state.json rather than an orphaned bare-ref stub.
- **Runtime image output delivery no longer duplicates attachments**.
- **CLI stdin pollution and input-dropping bugs in the Ink chat UI
  eliminated** — typing during a running turn no longer loses keystrokes.
- **Codex transient reconnect notifications downgraded to log level**
  (no longer spam the conscious session).
- **Notify "target not found" error now matches candidates scope-aware**
  (session_key prefix + channel kind), yielding actionable suggestions.

### Operational Tuning

- **Default cadence tick raised 5 min → 37 min**
  (`ALADUO_CADENCE_INTERVAL_MS`: 300_000 → 2_220_000). With the
  memory-weaver `cooldown_ticks: 5` unchanged, the effective minimum
  memory-write cadence moves from ~25 min to ~3 h — dramatically
  reduces prefix-cache invalidation from `memory/CLAUDE.md` rewrites.
  Set `ALADUO_CADENCE_INTERVAL_MS` in `~/.config/duoduo/.env` to
  restore the old cadence if your workload depends on it.
- **Sentinel subconscious partition retired**. 77-day production data
  showed 475 runs, $302 in model cost, 438K chars of output, and zero
  `.pending` files surfaced to the inbox. The checks it performed
  (session registry anomalies, job-state staleness, cadence queue
  backlog) are all filesystem-first state — they don't need an LLM to
  interpret. If an anomaly-surfacing need returns it will land as a
  TypeScript cron job, not a partition.

### Internal / Dependencies

- `@anthropic-ai/claude-agent-sdk` 0.2.114 → 0.2.119.
- Codex runtime label stripped of model version (decouples the label
  from whichever model codex happens to ship this week).
- `SessionIndex` is now the in-memory derived view of
  `var/sessions/<hash>/state.json` (completes Phase 3 of
  session-state-refactor; `var/registry/sessions/` is no longer read
  on the hot path and is archived to `var/registry.legacy.<ts>/` on
  first post-upgrade start).
- `session.archive` RPC + `duoduo session archive <session_key>` CLI
  retired the old ad-hoc deletion paths. Archive moves the session
  dir to `var/sessions-archive/`; recovery is `mv` back.

### Upgrade Notes

No migration required beyond restarting the daemon after install. The
first post-upgrade boot will run the legacy registry sweep once (logs
`[init] archived legacy var/registry/sessions/`), then the new index is
authoritative. Existing session artifacts on disk are untouched; only
the registry index is retired.

## [v0.5.0-rc.1] - 2026-04-19

First release candidate of the v0.5 line. Published to the `next` npm
dist-tag; `npm install -g @openduo/duoduo` keeps resolving v0.4.6 until
v0.5.0 ships as stable. Read the Upgrade Notes below before updating an
existing v0.4.x install — especially if you use a Feishu channel.

### Breaking / Migration

- **`@anthropic-ai/claude-agent-sdk` 0.2.92 → 0.2.114**: the Claude Code
  runtime is now a per-platform native binary delivered via optional
  dependencies (e.g. `@anthropic-ai/claude-agent-sdk-darwin-arm64`).
  Effects for upgraders:
  - Installing `@openduo/duoduo@0.5.x` automatically pulls a ~200 MB
    native binary for your platform. On slow networks this is the new
    long step.
  - Installs that pass `npm install --omit=optional` or set
    `NPM_CONFIG_OPTIONAL=false` complete, but the daemon refuses to
    start at boot with an actionable error naming the missing platform
    package. Reinstall without those flags, or set
    `CLAUDE_CODE_EXECUTABLE` to a compatible binary you already have.
  - A previously-installed global `@anthropic-ai/claude-code` package
    is no longer needed. Uninstalling it is safe; keeping it is
    harmless.
- **Feishu v0.5 main-session UX** (channel-feishu): owner DMs are now
  tied to a main session that's spawned automatically on first use and
  is immune to `/setup`; secondary DMs don't get the default workspace
  (`⌂`) entry; legacy DMs from pre-v0.5 remain usable. `FEISHU_BOT_OWNER`
  must be set in production — otherwise there is no owner-DM lock and
  the main-session guarantee is weakened. See the v0.5 admin skill for
  the full trust model.
- **`FEISHU_GROUP_CONTEXT_REMINDER` default flips on** (channel-feishu):
  the "since last reply" passive context capture introduced in v0.4.6
  as an opt-in is now enabled by default. Operators who want the old
  behavior can still set `FEISHU_GROUP_CONTEXT_REMINDER=0` / `false` /
  `no` in `~/.config/duoduo/.env`, but the flag is **deprecated** and
  will be removed in a future release — the capture behavior is
  stable enough that the per-deployment knob is no longer worth
  carrying.
- **Codex runtime auto-detection** (removes `ALADUO_CODEX_ENABLED`):
  the env flag that previously gated whether ManageJob exposed the
  `runtime: "codex"` option is gone. The daemon now probes
  `codex --version` and `codex login status` at boot: if the CLI is
  installed and the user is logged in, codex is advertised; otherwise
  it's hidden and any `runtime: "codex"` request silently falls back
  to Claude. Remove any `ALADUO_CODEX_ENABLED=...` line from
  `~/.config/duoduo/.env` — it's ignored now. `ALADUO_CODEX_SANDBOX`
  keeps working unchanged.
- **Third-party model endpoints**: compatible endpoints (sglang,
  LiteLLM proxies, older Bedrock/Vertex) that reject
  `thinking.type=adaptive` now surface the HTTP 4xx back to the user as
  a `[duoduo:drain-error]` reply instead of leaving the daemon silent.
  The common workaround is `DISABLE_ADAPTIVE=1 DISABLE_THINKING=1
  DISABLE_INTERLEAVED_THINKING=1 MAX_THINKING_TOKENS=0` in
  `~/.config/duoduo/.env`.

### New Capabilities

- **`duoduo onboard` subcommand**: dedicated, automation-safe entrypoint
  that runs the wizard and exits (no fall-through to the chat REPL).
  Reads all decisions from environment variables in non-TTY contexts
  (`ALADUO_RUNTIME_MODE`, `ALADUO_CLAUDE_AUTH_SOURCE`, `ALADUO_WORK_DIR`,
  `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL`,
  `DUODUO_ONBOARD_YES`). Exits with code 2 and prints the full env-var
  recipe on stderr when required inputs are missing, so the calling
  agent can self-correct.
- **`DUODUO_NODE_BIN` wrapper override** (#50): the `duoduo` bash
  wrapper honors this env as an absolute path to `node`, bypassing
  `PATH`. Lets GUI managers ship a private Node runtime and lets
  agents working inside `bash -lc` survive login-shell PATH resets.
- **Drain-error visibility**: when a daemon turn fails for any reason
  other than Skip/abort (SDK error, compatible-endpoint rejection,
  MCP failure), the runner now writes a `[duoduo:drain-error]`
  outbox reply to the anchor event's channel and a matching
  `agent.error` spine event, instead of silently dropping the turn.
- **Channel instance as a first-class citizen** (design doc +
  descriptor schema extension): descriptors carry `runtime`
  (`claude`|`codex`) and spawn provenance; new `channel.describe` /
  `channel.spawn` RPCs expose the instance lifecycle to channel
  plugins. Enables per-instance runtime selection without restart.
- **Feishu `/setup` slash command** (channel-feishu): setup card with
  hybrid permission model, per-channel `require_mention`, i18n-aware
  rendering (zh-CN default), dual-send card-action with owner DM cc,
  and "first-ingress" card that triggers before the first real reply.
- **`duoduo channel <kind> doctor` subcommand**: per-plugin three-layer
  diagnostic that runs while the plugin is stopped and prints a
  remediation checklist. Feishu implements it first (startup preflight
  + env validation).

### Bug Fixes

- Feishu channel: 10+ follow-up fixes from the v0.5 main-session round
  of adversarial review (setup card descriptor caching, spawn +
  activeSessionKeys ordering, button name validation, partial-update
  spawn, initial_option, display-text echo tolerance).
- Release: `build:release` now rebuilds every channel plugin bundle
  before packing, so the subsequent `pnpm pack` in each package picks
  up the latest code instead of stale `build:plugin` output.
- Stdio: removed the `/task` command and `TaskPanel` UI (the Task
  system was replaced by Jobs in v0.4.2).

### Infrastructure

- **Linux distribution verification harness**
  (`tests/distribution/linux/`): 5 end-to-end scenarios that install
  from the exact tarballs CI ships to npm and verify claude_code_local
  / anthropic_api_key onboard paths, the SDK preflight failure mode
  under `--omit=optional`, and a real `claude -p` agent driving
  `duoduo onboard` end-to-end (with a stdio ingress smoke test). All
  five are required to pass before tagging a stable release.
- **Release workflow pre-release handling**: tags containing a hyphen
  (`0.5.0-rc.1`, etc.) publish to the `next` npm dist-tag, set
  `--prerelease` on the GitHub Release, and do not assume `latest` on
  the Docker image.

## [v0.4.6] - 2026-04-14

### Features

- **stdio CLI terminal UX overhaul**: the stdio surface now uses a fullscreen
  Ink layout with scrollback rendered via `<Static>`, input history, typeahead
  command completions, and time-gap dividers that visually separate bursts of
  activity. Markdown rendering gains table and horizontal-rule support.
- **Feishu group context reminder** (channel-feishu 0.3.0): new opt-in
  `FEISHU_GROUP_CONTEXT_REMINDER` env var. When `true`, the Feishu channel
  passively captures non-mention group messages and surfaces the "since last
  reply" window as an additional context block the next time the bot is woken
  in that group. Default is `false`. State lives entirely inside the Feishu
  channel process and is dropped on restart — a daemon outage costs at most
  one wake's worth of passive context.

## [v0.4.5] - 2026-04-11

### Features

- **Job `keepalive` schedule type** (#44): a new cron value that runs once then keeps its session dormant. The conversation can be resumed later by sending a Notify to the job's session key — ideal for interactive worker use cases where the initial result may need follow-up questions or iterative refinement. Archive explicitly when done.

- **Periodic job mission as system prompt** (#45): job instructions are no longer re-sent as user messages on every cron tick. The mission is injected into the system-prompt append layer (new 6th layer in the prompt taxonomy), and each trigger sends a compact `<job-tick>` metadata block with `run_number`, `triggered_at`, and `previous_run_at`. Eliminates linear token bloat for periodic jobs and gives the model correct temporal awareness.

- **Versioned session schema upgrade**: new `schema_version` and `mission_fingerprint` fields in session state. Pre-existing job sessions are automatically upgraded to v1 on their first drain after deployment — no migration script, no operator intervention. The upgrade is one-time and crash-resilient (fires at most once per session, survives mid-drain crashes via atomic state writes).

- **Runtime-aware mission fingerprint guard**: when a job's mission file is edited (per the "everything is a file" design), the change takes effect on the next drain. On the Claude runtime, conversation history is fully preserved (zero cost). On the Codex runtime, the thread is rebuilt because `thread/resume` cannot accept new developer instructions (protocol constraint).

- **`ALADUO_TELEMETRY_ENABLED` env var**: set to `false` to disable `var/telemetry/*.jsonl` file persistence while keeping in-process debug telemetry logs intact. Exposed in `system.config` RPC and dashboard.

- **`ManageJob(list)` improvements**: every entry now includes `session_key` (for notify routing) and `runtime` (claude/codex). Keepalive entries carry a `note` explaining the dormant-but-wakeable lifecycle.

### Bug Fixes

- **Archive session tombstone** (#44): `ManageJob(archive)` now moves the session directory to `var/sessions-archive/` (symmetric with how job files are archived). Previously only the registry entry was deleted, leaving orphan session dirs that could be re-hydrated on daemon restart. This also fixes a pre-existing disk leak for `once` and `@in` jobs.

- **Delivery guard for archived sessions**: refuses delivery to archived sessions with a clean `session_archived` error, preventing phantom directory creation. Recreated sessions (archive + create with the same key) are correctly handled — the active directory takes priority over the stale tombstone.

- **Registry clear on mission guard reset**: the fingerprint guard now clears both `state.json` and registry `session_id` when forcing a session rebuild, preventing stale resume fallback.

- fix(notify): prevent hallucinated replies from task_notification (#41)
- fix(session): clear both state.json and registry on /clear to prevent stale resume

### Documentation

- **ManageJob tool description clarifications** (#43): `cwd_rel` now explicitly states that the runtime workspace is persistent (not a stateless sandbox). `instruction` explains the file-based mission editing contract.
- Design docs added for all three job-system features.
- Host Mode Deploy commands fixed to use `&&` and `daemon restart`.

## [v0.4.4] - 2026-04-07

### Features

- feat(codex): Codex app-server adapter (Phase 1) for running job sessions on GPT-5.4
  - Add `runtime` parameter to job definitions (`"claude"` | `"codex"`)
  - Dynamic tools bridge: aladuo MCP tools available to Codex sessions
  - Preflight check for codex CLI availability
  - `ALADUO_CODEX_ENABLED` feature flag and `ALADUO_CODEX_SANDBOX` env var
  - Auto-symlink `AGENTS.md` to `CLAUDE.md` for Codex sessions
- feat(dashboard): show KV cache hit rate in stats bar

### Performance

- perf(dashboard): add lightweight polling modes for `usage.get` and `job.list`
  - `usage.get` with `mode: "totals"` returns a single aggregate summary (~1KB vs ~230KB)
  - `job.list` with `summary: true` strips instruction content (~8KB vs ~60KB)
  - Dashboard polling bandwidth reduced by ~97%

### Bug Fixes

- fix(codex-adapter): add turnId notification filter and tool policy guard
- fix(codex-adapter): throw AbortError on turn abort for runner compatibility
- fix(job): serialize runtime field in frontmatter

### Security

- chore(deps): fix dependabot security alerts

## [v0.4.3] - 2026-04-05

### Bug Fixes

- fix(skip): suppress outbox via PreToolUse hook instead of post-drain state.json detection (#39)
  - Skip tool now sets an in-memory flag via SDK PreToolUse hook, eliminating disk I/O per turn
  - Runner checks `sdkResult.skipped` (simple boolean) to suppress outbox emission
  - Multi-turn drains are naturally correct — each turn carries its own flag
- fix(daemon): add `stream_end` to pull stream return_mask whitelist (#40)
  - The mask normalizer silently dropped `stream_end`, preventing channels from receiving
    stream cleanup notifications — typing indicators were never removed after Skip turns
- fix(daemon): forward ANTHROPIC_* env and apply onboard state on upgrade

### Features

- feat(daemon): launchd-based process management for macOS
- feat: add `kernel_dir` to `system.runtime.info` for contrib path discovery

### Internal

- refactor: simplify host onboarding auth flow
- Protocol bumped to 0.2.7 (`kernel_dir` field added to `RuntimeInfoResponse`)

## [v0.4.2] - 2026-04-02

### Bug Fixes

- fix(session-manager): enable streaming session resume after daemon restart (#34)
- fix(session-manager): close SDK query in stopStreamingSession to prevent cancel hang
- fix(drain-loop): break tight CPU-burning loop caused by orphan mailbox items
- fix(daemon): self-heal pre-migration cwd from registry to state.json

### Features

- feat(dashboard): display human-readable session names in status and event stream

## [v0.4.0] - 2026-03-31

### Features

- feat(observability): add last_error to session state and dashboard (17b4bfb)
- feat(session): add readAllSessionStates() for scanning state.json files (c63683f)
- feat(session): add pending-work hydration predicate (8001d43)
- feat(session-manager): add getActorView() and listActors() methods (adf46de)
- feat(session): reader fallback chain and session_key backfill (3fd1b1e)
- feat(session): dual-write cwd and watermark to state.json (779e219)
- feat(session): extend SessionRuntimeState with session metadata fields (fb7491f)

### Bug Fixes

- fix: keep Claude Code runtime defaults in process env (9d35a5d)
- fix(runtime): default ENABLE_TOOL_SEARCH=auto:5 for MCP tool discoverability (84e55c3)
- fix(channel-feishu): streaming card only updates currentText on confirmed sync (afe4a66)
- fix(session-manager): add drain cancelled flag and tighten stream_end emission (b0051a4)
- fix(job): wire system-level notify delivery and fix child job routing (9e7b13b)
- fix(gateway): /task kill surfaces cancel failure, start time falls back to registry (54e9e9b)
- fix(gateway): /task merges actor views with persistent sessions (29e660a)
- fix(daemon): system.status falls back to registry for pre-migration sessions (3aba562)
- fix: add getActorView/listActors to test mocks, fix SessionStatusEntry type (c10a659)
- fix: per-session merge for status views and live ManageSession status (32cb638)
- fix(cli): defer connection status until cwd_abs is resolved (4e545b8)
- fix(channel-feishu): skip sender prefix for slash commands in group chats (6e2b9a5)
- fix(session-manager): skip stale session ID resume in streaming mode (90c5bc6)
- fix(daemon): wait for process exit after SIGTERM before returning (e236d0c)
- fix(channel-feishu): accept null sender_id fields from bots with limited contact permissions (cf91a07)
- fix(daemon): eliminate race conditions in daemon stop lifecycle (b6ed9b3)
- fix(skip): remove self-preempt and emit stream_end on no-output drain (fd03ce4)
- fix(session-manager): use transport-level stop for /cancel on streaming sessions (6f9628d)

### Internal

- refactor: remove session_id from registry writes, single source cleanup (b6022ea)
- test: update session-manager and pool tests for registry write removal (77ac7d6)
- docs: session state refactor design (registry → derived view) (2122772)

### Other

- test(gateway): add reproducers for /task kill failure and registry timestamp fallback (f0fea4d)
- test(runner): check state.json for abort session_id instead of registry (acb73f4)
- test(session-manager): adapt 11 tests to registry hot-path write removal (97a18e3)
- refactor(session-manager): remove registry hot-path writes (6bd8fe4)
- refactor(daemon,gateway): migrate registry consumers to actor views with fallback (99f9822)
- refactor(tools): prefer state.json for session discovery in Notify (c57f6c5)
- refactor(tools): prefer state.json for status/cwd/sdk_session_id in ManageSession (e3eec25)
- refactor(tools): prefer state.json for cwd in QueueOutboundAttachment (e0690c1)


## [v0.3.7] - 2026-03-28

### Features

- **protocol**: Add `session.stream_end` notification for interrupted streaming turns. Channels can now clean up streaming UI (cards, typing indicators) when a turn is interrupted by Skip or preemption, preventing stale partial text from leaking across turns in group chat. ([#20](https://github.com/openduo/duoduo/issues/20))
- **session-manager**: Streaming turn admission control — new ingress enters a live CLI session without interrupting the active drain. When the CLI's result is delayed (e.g. background tasks polling), later messages are admitted into the same streaming session via a drain-scoped callback, keeping the session alive instead of killing and rebuilding it. ([#20](https://github.com/openduo/duoduo/issues/20))
- **daemon**: Expose runtime version in `system.runtime.info` RPC and ATC dashboard.

### Bug Fixes

- **session-manager**: Route `task_notification` to inbox regardless of streaming turn state. Previously, notifications arriving while a turn was active were silently swallowed as generic system events. ([#20](https://github.com/openduo/duoduo/issues/20))
- **session-manager**: Deny `Bash(run_in_background=true)` via PreToolUse hook. CLI's polling loop only activates for `local_agent` task types, causing completion notifications for 2nd+ concurrent Bash background tasks to be silently dropped. The hook directs the agent to use `Agent(run_in_background=true)` instead, which is 100% reliable.
- **channel-feishu**: Resolve `@mention` placeholders to readable user names and enforce group command security.
- **cli**: Use runtime node binary for channel plugin start instead of install-time path.

### Dependencies

- Upgrade `@anthropic-ai/claude-agent-sdk` from 0.2.63 to 0.2.81.

### Documentation

- Add streaming turn lifecycle design doc (`docs/refactor-streaming-turn-resolution.md`).
- Document Bash `run_in_background` notification drop as SDK limitation with full root cause analysis.
- Add Host Mode Deploy SOP for pre-release testing.


## [v0.3.6] - 2026-03-24

### Features

- **logging**: Add `trace` log level below `debug`. Read-only polling RPCs (`spine.tail`, `system.status`, `usage.get`, `job.list`) are demoted from debug to trace, cutting daemon log volume by ~80% at the default debug level.

### Bug Fixes

- **session-manager**: Prevent permanent session hang when the SDK subprocess exits before consuming any prompt ([#15](https://github.com/openduo/duoduo/issues/15)). The streaming session now tracks a `closed` state and rejects dangling/late turns so the drain loop can recover on the next wake instead of stalling forever.
- **session-manager**: Route background subagent `task_notification` messages to session inbox when they arrive after the current turn has already resolved. Previously these were silently dropped.
- **session-manager**: Release concurrency pool slots when sessions enter idle state. Idle resident sessions no longer count against the channel/job concurrency limit, allowing queued sessions to start without waiting for idle timeout.

## [v0.3.5] - 2026-03-24

### Bug Fixes

- **cli**: Fix ESM self-invocation guard failing when install path contains spaces ([#11](https://github.com/openduo/duoduo/issues/11)). The CLI would silently exit with code 0 producing no output at all. Now uses `pathToFileURL()` for correct URL encoding.
- **agent-sdk**: Escalate abort recovery for unresponsive SDK subprocesses so reset/cancel paths can force-close a stuck turn without leaving abandoned work behind.
- **runner**: Keep session lock heartbeat and release ownership inside the active drain so actors that never acquired the lock cannot renew or delete it.

## [v0.3.4] - 2026-03-23

### Bug Fixes

- **session-manager**: Force-kill unresponsive SDK turns that exceed graceful shutdown timeout.
- **runtime**: Guard session lock release so only the owning runner can unlock.
- **runner**: Preserve interrupted context on late aborts instead of discarding partial results.
- **agent-sdk**: Strip internal environment variables from child process env to prevent leaking into spawned sessions.
- **daemon**: Stop clearing channel capabilities on WebSocket close ([#9](https://github.com/openduo/duoduo/issues/9)).
- **feishu**: Scope host dotenv loading to channel start to avoid polluting daemon env.
- **feishu**: Detect image MIME type from magic bytes instead of hardcoding `image/png`.


## [v0.3.3] - 2026-03-19

### Features

- **daemon**: `system.config` RPC — inspect effective runtime configuration (network, sessions, cadence, SDK, paths) with source tracking (`env` / `default` / `unset`).
- **cli**: Host-side `.env` file support — daemon command auto-loads dotenv before starting.
- **dashboard**: Render `channel.message` and `channel.command` as ingress events in the event stream.
- **feishu**: Clarify allowlist entity semantics and add gateway ENV_ARGS passthrough.
- **bootstrap**: Expand subconscious and working-memory partition guidance.

### Bug Fixes

- **daemon**: Per-consumer channel capabilities to prevent overwrite race ([#7](https://github.com/openduo/duoduo/issues/7)).
- **daemon**: Handle `system.shutdown` method to defer SIGTERM response until cleanup completes.
- **cli**: Validate remote daemon shutdown before reporting success.
- **session-manager**: Align disallowed tools list with `DEFAULT_DISALLOWED_TOOLS` for consistency.
- **agent-sdk**: Extend `DEFAULT_DISALLOWED_TOOLS` to include additional unsafe tools.
- **feishu**: Clean typing indicators for coalesced ingress messages.
- **cadence**: Simplify partition context injection; fix channel output delivery and registry hydration.


## [v0.3.2] - 2026-03-18

### Features

- **dashboard**: Single-file ATC monitoring panel served at `GET /dashboard` on the daemon port. Zero dependencies, replaces the previous React+Vite SPA. Signal bar with shape-coded indicators (circles=sessions, squares=cron jobs, diamonds=one-shot jobs), unified color semantics, rich event stream with inline markdown rendering, auto-follow with DOM recycling.
- **protocol**: Add `system.status` RPC (health, sessions, subconscious playlist) and `spine.tail` RPC (last N events with incremental `after_id` cursor and cross-midnight boundary support).
- **runner**: Expose `tool_input_delta` in `session.execution` notifications for progressive tool input rendering.

### Bug Fixes

- **dashboard**: Show working directory (cwd) in signal tooltips for sessions and jobs; use diamond shape for one-shot jobs (`@in`, `@once`).
- **session-manager**: Write `ended` status to registry when drain loop exits — previously only per-session runtime state was updated, leaving job sessions stuck in "active" status indefinitely.
- **cadence**: Disambiguate partition-local paths from shared memory in subconscious context.
- **runtime**: `bootstrapDir` fallback uses package root instead of `process.cwd()`.
- **runner**: Fix `input_summary` serializing as `[object]` when tool input is undefined.

## [v0.3.1] - 2026-03-17

### Performance

- Cross-cutting runtime I/O optimizations — caching, append-only mailbox, sharded registry, and lazy reads across hot paths.

### Bug Fixes

- **cadence**: Settle subconscious partition scheduling — fix round-robin stalls and idle-tick fanout.
- **replay**: Validate warm freshness against replay file state to prevent stale cache hits.
- **cli**: Reject pending RPC requests on graceful WebSocket close instead of leaking promises.
- **postinstall**: Restore execute permission on vendored ripgrep binaries after npm install.

## [v0.3.0] - 2026-03-15

### Features

- **runner**: Add configurable time-gap session context and upgrade runtime prompt assembly to structured content blocks.

### Bug Fixes

- **runtime**: Split outbox replay bootstrap read/write paths so live appends no longer rebuild replay artifacts on every write.
- **replay**: Harden session-local cursor fallback and recovery when replay indexes are incomplete or stale.

## [v0.2.12] - 2026-03-12

### Bug Fixes

- **runtime**: Stabilize job scheduling state — prevent duplicate spawns and stale cron evaluation.
- **cli**: Add `command` field to generated `docker-compose.yml` so the container starts correctly.
- **feishu**: Preserve customer-service copy bindings across restarts and remove deprecated `/cs` commands.

### Features

- **cli**: Read Claude settings (API keys, model config) during onboard flow.

## [v0.2.11] - 2026-03-11

### Bug Fixes

- **runtime**: Repair Claude runtime settings backfill so upgraded kernels recover from malformed existing `settings.json` env blocks instead of failing during init.
- **feishu**: Serialize typing/reaction transitions with outbound delivery so transient typing hints do not race or disappear before the final reply path completes.

## [v0.2.10] - 2026-03-11

### Bug Fixes

- **feishu**: Fix zombie streaming card race — unified notification chains so stream chunks always complete before final output is processed. Introduces content lane (stream + output, strict serial) and hint lane (execution, fire-and-forget) two-lane model.
- **feishu**: Honor routed workspace in handshake and routing.
- **feishu**: Detect and handle streaming card 30KB content limit with automatic fallback.

### Features

- **protocol**: Extend runtime info with channel defaults.

## [v0.2.7] - 2026-03-08

### Features

- feat(channel): add installFromNpm method and enhance install target detection (4260f08)

### Bug Fixes

- fix(daemon): bind to 127.0.0.1 by default, expose ALADUO_DAEMON_HOST for containers (09b1d94)
- fix(channel-feishu): add fetch timeout to streaming card to prevent outputChain deadlock (9b17d5b)


## [v0.2.5] - 2026-03-07

### Features

- feat(cli): wire container v2 subcommands into main entry and onboard flow (5319290)
- feat(cli): add docker-exec helpers for container lifecycle management (4245a13)
- feat(cli): add duoduo-yaml instance config parser and generator (bcf8ef9)

### Internal

- docs: rewrite README for npm publishing — principles only, no internals (2b4fd26)

### Other

- refactor(cli): rewrite container-command with v2 subcommand dispatch (3b2b8c8)
- refactor(runtime): update paths resolution and init logic (b8a0874)
- docs(design): add container instance v2 design doc (56567c9)


## [v0.2.4] - 2026-03-06

### Bug Fixes

- fix(runtime): add safe.directory for cross-UID bind-mounted kernel dir (2c74a47)
- fix(test): check descriptor subdirs instead of any file in channelsDir (472a3cc)
- fix(test): update default container image to ghcr.io/openduo/duoduo (3715ad8)
- fix(feishu): inject createRequire banner to fix ESM dynamic require error (c4144cc)

### Internal

- docs: remove pre-existing test failures from CLAUDE.md (3ec05ca)


## [v0.2.2] - 2026-03-05

### Bug Fixes

- fix: bundle claude-cli.js and react-devtools-core stub into dist/release (b2a3d94)