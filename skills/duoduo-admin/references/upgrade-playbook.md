# Upgrade playbook (host mode)

Load this reference when the user asks to upgrade duoduo — especially
when they mention v0.5, "升级 duoduo", "升级到 v0.5", or a specific
version bump.

## Upgrading from inside a session (read this first if you are an agent)

If you are an agent running inside a duoduo session and the user asked you to
upgrade the host, **the daemon restart will kill you mid-command.** The restart
tears down the session-manager, which kills every SDK subprocess — including
the one running your Bash tool. Anything you planned to do after the restart
does not happen, and you cannot report that, because the turn dies too.

This is not hypothetical: on 2026-08-05 an agent upgraded a production host
this way, stopped the Feishu gateway, restarted the daemon, and died there.
The gateway stayed down and the bot silently accepted messages without
answering until a human noticed.

**On every released version up to and including v0.7.0, there is no safe way
to upgrade from inside a session — including `duoduo upgrade`.** Ask the user
to run it from a terminal, or over SSH. Both are outside the daemon's process
tree and unaffected.

Two ways the attempt fails, neither of which reports anything:

- **`duoduo upgrade`** stops the gateways, restarts the daemon, and dies before
  restarting them. Worse than doing nothing, because it leaves them stopped.
- **Manual step-by-step** (`npm install -g`, then `duoduo daemon restart`) ends
  your turn at the restart, with the channels in whatever state you left them.

From **v0.7.1** `duoduo upgrade` detects this case and hands the run to a
detached process that the restart cannot reach, printing a log path first; pass
`--wake <your-own-session-alias>` to be notified once the gateways are back.
There is no flag for it and nothing in `--help` to detect — it is automatic, so
the version is the only signal. When it engages it says so, printing
"upgrade handed off to a detached process" before this turn ends.

Running from a terminal, over SSH, or from DuoduoManager? None of this applies
— you are not in the daemon's process tree.

## One-line summary

Standard upgrade is two commands:

```bash
npm install -g @openduo/duoduo@latest
duoduo daemon restart -r "upgraded @openduo/duoduo to <version>"
```

**Crossing into v0.7.0 needs a third step: reinstall and restart every
channel.** The gateways connect to the daemon over a unix socket from
that release on, so a gateway still running its old build cannot reach
the upgraded daemon — the bot accepts messages and answers none. See
"Transport change landing in v0.7.0" below; that section is mandatory
reading for this upgrade, not a footnote.

The rest of this playbook only matters when (a) the user is crossing
the v0.5 boundary AND has a Feishu channel, or (b) something goes
wrong and we need to fall back to first-principles.

### Prefer `duoduo upgrade` where it is available

On newer builds one command does both steps and does them better:

```bash
duoduo upgrade                 # or: duoduo upgrade 0.6.4
```

Detect support from the CLI, not from a version number: `duoduo --help`
shows `--wake` on the upgrade line exactly when this behavior is
present. Older builds ship a `duoduo upgrade` that takes only a version
and has none of the properties below — on those, use the two-command
form.

It is not just shorter. It installs into the prefix that owns the
**binary currently running**, which the manual `npm install -g` does
not: if duoduo was installed outside npm's default global prefix (the
DuoduoManager menubar app does exactly this), the manual command
installs a second copy elsewhere, leaves the running binary untouched,
restarts the old daemon, and reports success. It also fills in the
restart reason from the version it actually resolved, and waits for
the new daemon to pass a health check instead of assuming it booted.

From v0.7.0 on it **also upgrades the channel plugins** — installing
each one, restarting the daemon, then bringing the channels back, in an
order where a channel whose download failed keeps running its previous
build instead of being stopped. This is the step people forget when
upgrading by hand. Note it cannot help the upgrade that *introduces*
it: an upgrade run from a pre-0.7.0 CLI executes the old code, so
crossing into v0.7.0 still needs the channels reinstalled manually.

Every running instance of a channel is handled the same way: a second
Feishu or Lark app (`--instance <name>`) is stopped before the daemon
restart and started after it; instances that were stopped stay stopped.

A host that already aliased a channel session `main` keeps it as main;
two such sessions are reported, not merged — see `duoduo-runtime-admin`
→ `references/main-session.md`.

If a session was mid-turn and should be told, the same flag applies:

```bash
duoduo upgrade --wake <session-or-alias>       # repeatable
```

On older versions, and any time you want the steps separated, use the
two-command form above — it works on every version.

## Step 1 — Preflight (accelerator)

Run the preflight script to collect upgrade-relevant facts in one
pass:

```bash
bash scripts/v05-upgrade-preflight.sh
```

Output is markdown. Look for the "Recommended branch" section at the
bottom — it names one of **Branch B / C / D** described below.

### If the preflight script is unavailable or errors

Reproduce each probe manually (every section of the script is
documented here so the agent can skip the script entirely):

```bash
duoduo --version                       # installed version (see note below)
npm view @openduo/duoduo version       # latest published
duoduo daemon status                   # daemon running?
duoduo channel list                    # any feishu / acp?
grep -E '^[[:space:]]*FEISHU_(BOT_OWNER|ALLOW_FROM|ALLOW_GROUPS|DM_POLICY|GROUP_POLICY|GROUP_CMD_USERS)[[:space:]]*=' \
  ~/.config/duoduo/.env                # security env snapshot; the last line of a key wins
ls ~/.aladuo/var/channels/feishu-*/descriptor.md 2>/dev/null
for d in ~/.aladuo/var/channels/feishu-*/; do
  grep -E '^bound_by:' "${d}descriptor.md" || echo "  (no bound_by — pre-v0.5)"
done
```

`duoduo --version` failing with a daemon WebSocket error is not a broken
install: the flag hit the chat path instead of printing, a bug present in
every build up to and including v0.8.1 and fixed after it. Read the version
off `duoduo daemon status` and carry on with the branch decision.

Then decide the branch by hand:

- No feishu channel installed → **Branch B**.
- Feishu installed AND any of these → **Branch D**:
  - `FEISHU_BOT_OWNER` unset. If `FEISHU_ALLOW_FROM` is set, its first
    entry acts as owner: confirm that is the owner and set
    `FEISHU_BOT_OWNER` explicitly. If both are unset, every DM is denied;
  - `FEISHU_DM_POLICY` is `open` or `pairing`;
  - at least one bound group, `FEISHU_ALLOW_GROUPS` empty, and
    `FEISHU_GROUP_POLICY` not `open`.
- Feishu installed and none of the above (`FEISHU_BOT_OWNER` set and
  `FEISHU_DM_POLICY` neither `open` nor `pairing`) → **Branch C**.

These keys are the default instance's, in `~/.config/duoduo/.env`. A named
instance reads only `~/.config/duoduo/feishu.<name>.env`, and its
descriptors are `feishu-<name>-oc_<chat_id>/`; check it the same way.

A bound group is a `var/channels/feishu-oc_<chat_id>/` descriptor whose
chat is a group. The directory name does not say so — a DM chat id also
starts with `oc_`. A group's session key has no `ou_` part:

```bash
for d in ~/.aladuo/var/channels/feishu-oc_*/; do
  id="${d%/}"; id="${id##*/feishu-}"
  grep -lE "\"session_key\": *\"lark:${id}:[0-9a-f]{12}\"" \
    ~/.aladuo/var/sessions/*/state.json >/dev/null 2>&1 && echo "group: ${id}"
done
```

A group that has never run a session does not show up; it needs listing
all the same.

## Step 2 — Pick the branch

### Branch A — fresh install (not really an upgrade)

Skip this playbook. Send the user to onboarding (`duoduo` CLI from
empty state). Nothing v0.5-specific to discuss until they have a
channel configured.

### Branch B — upgrade, no Feishu

```bash
npm install -g @openduo/duoduo@latest
duoduo daemon restart -r "upgraded @openduo/duoduo to <version>"
```

Then verify:

```bash
duoduo --version                      # should show 0.5.x now
duoduo daemon status                  # healthy: yes; version: 0.5.x
```

Done. No further v0.5-specific action needed — the trust-boundary
changes only affect the Feishu channel.

### Branch C — upgrade with Feishu + security env already set

Safe to proceed. The agent should:

1. Run the upgrade:
   ```bash
   npm install -g @openduo/duoduo@latest
   duoduo daemon restart -r "upgraded @openduo/duoduo to <version>"
   ```
2. Restart the Feishu plugin to pick up the new plugin bundle (the
   plugin is a separate process; daemon restart does not restart it):
   ```bash
   duoduo channel feishu stop
   duoduo channel feishu start
   ```
3. Verify:
   ```bash
   duoduo --version
   duoduo channel list                # feishu shows @openduo/channel-feishu@0.5.x, running
   ```
4. Brief the user on the two new /setup behaviors they'll observe:
   - Owner DM (their personal DM with the bot): first message
     auto-spawns the owner DM session; no setup card.
   - Groups: already-configured groups now show a compact "current
     configuration" card (mention toggle only) on `/setup`.

Hand off to `duoduo-channel-admin` → `references/feishu.md` for the
full behavior matrix if the user wants to see every case.

### Branch D — upgrade with Feishu but missing security env

⚠️ **Discuss with the user BEFORE running the upgrade.** Both access
policies default to `allowlist`. A denied message gets the plain-text reply
「抱歉，您没有权限与此机器人对话。如需访问，请联系管理员。」.

- No `FEISHU_BOT_OWNER` and an empty `FEISHU_ALLOW_FROM`: every DM gets
  that reply after the upgrade.
- Bound groups with `FEISHU_ALLOW_GROUPS` empty: every bound group gets
  that reply (to every message the bot receives there) until its chat_id is
  listed. Senders in `FEISHU_ALLOW_FROM` still get through.
- An explicit `FEISHU_DM_POLICY=open` (or `pairing`, which behaves the
  same): any first DM sender auto-spawns an owner-style DM session, so
  strangers who reach the bot get that unrestricted session.

Walk the user through:

1. Confirm the bot owner's Feishu open_id. Ask them to /whoami in
   an existing chat with the bot, OR grep Feishu developer console.
2. Propose additions to `~/.config/duoduo/.env`:
   ```bash
   FEISHU_BOT_OWNER=ou_<theirOpenId>
   FEISHU_ALLOW_FROM=ou_<theirOpenId>,ou_<friend>,...   # if not already set
   FEISHU_ALLOW_GROUPS=oc_<group>,...                   # every bound group to keep
   ```
   For `FEISHU_ALLOW_GROUPS`, the chat ids are the `feishu-oc_<chat_id>`
   descriptor names of the groups found above. Remove an explicit
   `FEISHU_DM_POLICY=open` or `pairing` line; unset means `allowlist`.
3. Show the diff with the existing `.env` and ask for confirmation
   before writing (sensitive file).
4. Write the additions using
   `duoduo-runtime-admin`'s
   [scripts/update_host_env.py](../../duoduo-runtime-admin/scripts/update_host_env.py)
   if available, otherwise hand-edit.
5. Then proceed with Branch C's upgrade + restart sequence.

If the user refuses to set security env right now, document the
risk in chat and let them proceed into "bootstrap mode" with their
eyes open. Do not block the upgrade — but do warn explicitly.

### Pre-v0.5 descriptors (legacy groups / DMs)

The preflight marks each existing descriptor as "v0.5 (has bound_by)"
or "pre-v0.5 (no bound_by — legacy binding)". Legacy descriptors
continue to work without migration. Their `/setup`:

- Groups: fall back to `FEISHU_GROUP_CMD_USERS` allowlist for the
  compact rebind card's permission check.
- p2p (DMs): route through the secondary-DM card path (no ⌂) so
  the user can still reassign project.

No action required for legacy descriptors unless the user reports a
specific problem with one.

## SDK architecture change landing in v0.5

v0.5 upgrades the bundled `@anthropic-ai/claude-agent-sdk` to
0.2.114, which ships the Claude Code runtime as a per-platform
native binary via npm optional dependencies (e.g.
`@anthropic-ai/claude-agent-sdk-darwin-arm64`). Implications for
upgraders:

- `npm install -g @openduo/duoduo@0.5.x` will download the
  platform-specific binary (~200 MB) automatically. On slow
  networks this is the new long step; previous versions only
  fetched JS.
- Installs with `npm install --omit=optional` or
  `NPM_CONFIG_OPTIONAL=false` will succeed but the daemon will
  refuse to start, with an actionable error naming the missing
  `@anthropic-ai/claude-agent-sdk-<platform>-<arch>` package.
  Reinstall without the flag, or set `CLAUDE_CODE_EXECUTABLE`
  to a compatible binary you already have. From the fixed v0.5
  patch line onward, successful host onboarding with
  `CLAUDE_CODE_EXECUTABLE` set persists that value in
  `~/.config/duoduo/.env`, and macOS launchd daemon starts forward
  the same value into the daemon environment.
- Users who previously installed `@anthropic-ai/claude-code` as
  a separate global package can uninstall it — duoduo now carries
  its own copy via the SDK. Keeping the standalone install is
  harmless but not required.
- Third-party compatible endpoints (sglang, LiteLLM proxies,
  older Bedrock/Vertex) may reject `thinking.type=adaptive`
  requests with HTTP 4xx. The daemon now surfaces this as a
  `[duoduo:drain-error]` reply instead of silence. The common
  workaround is setting `DISABLE_ADAPTIVE=1 DISABLE_THINKING=1
  DISABLE_INTERLEAVED_THINKING=1 MAX_THINKING_TOKENS=0` in
  `~/.config/duoduo/.env` and restarting the daemon.

## Runtime selection changes landing in v0.5.3

v0.5.3 treats Claude and Codex as peer runtime choices when both are
available on the host. Claude remains the default fallback, so existing
operators do not need to change anything unless they want Codex routing.

- Codex is listed as available when `codex --version` succeeds. Turns
  also need `codex login`, which takes no restart. Message routing
  re-probes while codex is unavailable; restart the daemon only so
  channel setup cards and ManageJob list codex.
- To route one channel kind to Codex, set `runtime: codex` in
  `kernel/config/<kind>.md`.
- To route one channel instance to Codex, prefer the channel setup flow
  when the channel provides one; otherwise update that instance
  descriptor deliberately.
- To make Codex the fallback for every actor without a more-specific
  declaration, set `ALADUO_DEFAULT_RUNTIME=codex` in
  `~/.config/duoduo/.env` and restart the daemon.

Do not tell users that an existing live conversation hot-swaps runtimes
the moment a default changes. A session stays bound to the runtime that
owns its conversation, and a runtime-only change refuses its next turn.
For a clean switch, `/clear` the session first, then change the runtime
(see "Switching a session's runtime" in `duoduo-runtime-admin`). Codex
that is unavailable refuses the turn; it no longer falls back to Claude.

## Grok as a third peer runtime

Grok is auto-detected: install the `grok` CLI, then run `grok login`
(duoduo probes only the binary). Set `runtime: grok` on a kind, instance,
job, or partition, or `ALADUO_DEFAULT_RUNTIME=grok` for a global default.

An explicit or default grok that cannot be served is a **hard failure**
— there is no silent fallback to Claude (Codex now behaves the same). `prompt_mode`
applies to claude and grok; combining it with `runtime: codex` is still
rejected.

See the grok-runtime reference under `duoduo-runtime-admin`. Do not set
`GROK_HOME`.

## Built-in tool surface change landing in v0.5.10

v0.5.10 flips the claude runtime's built-in tool surface from a denylist to
an **allowlist**: every session gets a fixed core set, and descriptors
add extras via the nested `claude.tools` frontmatter key (kind ∪ instance
union, additive-only). No file migration is required — upgrade + daemon
restart applies it to every session's next turn, and rollback is safe (older
versions ignore the `claude:` block).

The core was 16 names in v0.5.10 and is **15 from v0.8.2**: the Agent SDK
deleted `TaskOutput`, the tool a model used to poll a background agent for its
output. Background agents now notify the model when they settle, so nothing
replaced it. Subconscious partitions get a 6-name file-work core.

Two descriptor recipes change meaning; check for them during preflight:

- `allowedTools: [WebSearch]` (the old re-enable recipe) no longer adds any
  tool — move the names to `claude: { tools: [...] }`. `allowedTools` keeps
  its SDK meaning (permission auto-approve) only.
- `disallowedTools` with built-in names (e.g. `Bash`) no longer blocks them —
  the daemon warns and ignores such entries, and a core tool listed there
  becomes available again after upgrade. `disallowedTools` remains effective
  for MCP tools (`mcp__…`) only.

Both stale recipes usually announce themselves after the upgrade: the
daemon logs a `[claude-sdk]` warning naming the stale entries and
pointing at `claude.tools`, once per session subprocess. Do not treat a
silent log as proof of a clean descriptor — a built-in listed in
`allowedTools` **and** `disallowedTools` is dropped before the warning
can fire, so that combination is a no-op nobody announces. Inspect any session's
effective surface with `duoduo session config <target> get` (read-only
`claude_tools` block). Full semantics: `duoduo-channel-admin` →
`references/channel-config-model.md#built-in-tool-surface-allowlist`.

## Transport change landing in v0.7.0

v0.7.0 moves the daemon's full-access interface off TCP and onto a unix
socket (`<runtime>/run/daemon.sock`, owner-only). `127.0.0.1:20233`
survives as a **read-only** surface for the dashboard and speaks no
WebSocket. Nothing about this is optional or gradual — both sides flip
at the restart.

**The upgrade step people miss: channels must be reinstalled.** A
gateway built before v0.7.0 dials the TCP port for its control
connection and gets refused by the upgraded daemon. Symptom, and it is
a quiet one: the bot keeps *receiving* messages and answers none — the
user sees read-but-no-reply. The gateway's own log goes silent after a
few reconnect lines; the signal that identifies it is on the daemon
side.

```bash
# after the core upgrade + daemon restart, per channel:
duoduo channel <kind> install
duoduo channel <kind> stop && duoduo channel <kind> start
```

Verify — all three should hold:

```bash
ls -l <runtime>/run/daemon.sock                  # srw------- (owner-only socket)
curl -s -X POST http://127.0.0.1:20233/rpc \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"session.list","params":{}}'
                                                 # -32601, method not available
duoduo channel list                              # every channel you use: running
```

A `426` in the daemon log (`pre-hardening client dialed /ws`) means a
gateway is still on the old build — that is the detector for "someone
forgot to reinstall a channel", and it repeats until fixed.

Two more consequences worth stating before someone trips on them:

- **`ALADUO_DAEMON_HOST` changed meaning.** It no longer moves the main
  port. The read-only port is pinned to loopback regardless. The
  variable now selects the bind address of the optional remote
  listener, which refuses to start unless `ALADUO_REMOTE_PORT` and a
  token (`duoduo daemon token new`) are also present. A host that
  previously set this to expose the daemon on a LAN address was
  publishing an unauthenticated control interface; that configuration
  now fails closed instead of starting.
- **A locally-configured `ALADUO_DAEMON_URL` pointing at
  `127.0.0.1:20233` keeps working.** The CLI recognises it as the old
  default and uses the socket instead. Do not "fix" such a value by
  pointing it somewhere else.

Rollback is a downgrade of both core and channels together; a new
daemon with old channels and an old daemon with new channels both fail
the same way.

## Feishu card settings landing in v0.8.0

v0.8.0 deletes both `ALADUO_EXP_FEISHU_*` env gates. They are not renamed
and not deprecated — the channel package's `envAllowlist` no longer carries
them, so the keys never reach the channel process at all.

**`ALADUO_EXP_FEISHU_CARD_FOOTER` needs no action.** The card footer is now
unconditional: it renders whenever the turn reports usage. A host that had
the flag on sees the same cards as before, and one that had it off gains the
footer.

**`ALADUO_EXP_FEISHU_PROCESS_CARD=1` is the one that bites.** The process
card is now selected per channel in config, and the default is `off`, so a
host that was running the experiment loses the process card at the upgrade
with nothing in the log to say why. Put it back in `config/feishu.md` (every
Feishu channel) or in one instance descriptor (that channel only):

```yaml
feishu:
  process_card: replace   # replace = one card; keep = process card + result card
```

`replace` matches the old `ALADUO_EXP_FEISHU_PROCESS_CARD=1` with
`ALADUO_EXP_FEISHU_KEEP_PROCESS_CARD` unset; `keep` matches having both set.
Both files are read on every message, so the change takes effect on the next
message — no channel restart, unlike the flag it replaces. Delete the dead
keys from `~/.config/duoduo/.env` in the same pass; nothing warns about them.

## Subconscious partition retirement landing in v0.8.0

v0.8.0 replaces the `memory-weaver` partition with the
`gradient-distiller` + `intuition-weaver` pair and removes the
`cadence-executor` partition (its signal kinds post directly to
`intuition-weaver`). Fresh installs never see the old partitions;
upgraded hosts still have their directories on disk, and the first
daemon start after the upgrade retires them automatically:

All four conditions must hold before anything is written, which is
what decides whether a host's own edits survive:

1. The directory is named `memory-weaver` or `cadence-executor`.
2. Its `CLAUDE.md` still declares itself the official partition of
   that name — the weaver by a `contract:` block naming itself, the
   executor by having no `contract:` block at all. **Note what this
   does and does not protect: a rewritten prompt is still retired.**
   Partitions self-program, so the migration deliberately does not
   fingerprint the text; what spares a directory is having been
   *repurposed* — a contract naming some other partition, or a
   contract appearing where the executor never had one.
3. The frontmatter literally says `enabled: true`. A charter with no
   `schedule` block is skipped, even though the scheduler would treat
   that as enabled — writing a schedule block into a file that never
   had one is a bigger edit than a migration should make.
4. No marker on disk yet.

The flip sets `schedule.enabled: false` and writes a marker at
`<runtime_dir>/var/meta/partitions/<name>.retired`. The marker is
written **first**, so a crash between the two writes degrades to a
silent skip rather than to re-flipping a switch an operator had turned
back on. An existing marker is never re-applied — a manual re-enable
sticks, and is the rollback path for one host. The directories are
never deleted; `npm install` merges, it does not remove.

The two replacement partitions arrive through the normal bootstrap
merge on upgrade. Their prompts, like all shipped partition prompts,
are NOT auto-upgraded afterwards — see the refresh section below.

## Agent tool-surface change landing after v0.8.1

The release after v0.8.1 moves job lifecycle off the agent's tool surface and
onto the CLI, and gives a session a way to schedule its own next turn. Nothing
on disk migrates; the change is what the model sees and what the operator
types.

- Ending and re-timing a job are shell verbs — `duoduo job archive`,
  `duoduo job interrupt` (which takes a required reason), and
  `duoduo job reschedule`, beside the existing `list` and `read`. The agent
  tool keeps creating, listing and reading jobs, and no longer archives or
  reschedules them.
- A session can schedule one future turn of itself, and an operator can
  schedule one for a session with `duoduo session wake <key> --in <duration>`
  (context on stdin). Pending wakes show up in `duoduo job list` and are
  cancelled with `duoduo job archive <wake-id>`.
- The session-inspection tool is read-only and now lists every active session
  when called with no argument, which is how an agent finds a target to notify.

**The upgrade step people miss: live codex sessions keep the old tool list.** A
codex thread caches its tools at thread start, so after the upgrade it keeps
calling the retired actions; the daemon answers with an error naming the verb
that replaced them, but the model cannot discover the new surface by itself.
Have each codex session's owner run `/reset`, and say first that this starts
the session on a fresh thread and drops its history. Claude and Pi sessions
need nothing.

One bug fix worth knowing during preflight: `duoduo --version` used to exit
with a daemon WebSocket error instead of printing a version. It prints now.

## Changes landing in v0.8.4

**Check every written runtime value before upgrading.** Up to v0.8.3 a
runtime value duoduo did not know (a typo such as `runtime: codx`) was
dropped without a word: a channel or partition fell through to the next
layer (instance, then kind, then the global default), often but not always
Claude, and an invalid `ALADUO_DEFAULT_RUNTIME` fell back to Claude. From
v0.8.4 it is refused with a sentence that names the value and the valid ones:

| where the value is written | after the upgrade |
| --- | --- |
| `ALADUO_DEFAULT_RUNTIME` in `~/.config/duoduo/.env` | the daemon does not boot (absent or empty still means `claude`) |
| a channel kind or instance descriptor | turns are refused ("Request was not executed") for sessions whose runtime that layer selects; a valid instance value overrides an unknown kind value |
| job frontmatter | the job fails |
| subconscious partition frontmatter | the partition is skipped |

Model runtimes are `claude`, `codex`, `grok` and `pi`. Channel configuration
also accepts `void`, meant for plugins such as tether whose sessions never
run a model; do not set it on an ordinary chat channel (see
`duoduo-channel-admin`). Find every written value first, with the paths
from `duoduo daemon config`:

```bash
grep -n 'ALADUO_DEFAULT_RUNTIME' ~/.config/duoduo/.env
grep -rn --include='*.md' '^runtime:' <kernel_dir>/config <kernel_dir>/subconscious \
  <runtime_dir>/var/channels <runtime_dir>/var/jobs/active
```

Fix a misspelled value to the runtime the sessions it governs have actually
been running on — the layer it fell through to, not necessarily Claude.
Writing a different runtime refuses their next turn unless you `/clear` them
first (see "Switching a session's runtime" in `duoduo-runtime-admin`).

**Rename pi's built-in DeepSeek Flash id before upgrading.** The bundled pi
1.0 no longer has `deepseek/deepseek-v4-flash`; upstream renamed it
`deepseek/deepseek-flash`. A `model:` pin that names the old id — partition
or job frontmatter, a channel config, a stored `/model` choice — no longer
resolves after the upgrade. Find and change it:

```bash
grep -rn 'deepseek/deepseek-v4-flash' <kernel_dir>/config <kernel_dir>/subconscious \
  <runtime_dir>/var/channels <runtime_dir>/var/jobs/active <runtime_dir>/var/sessions
```

A stored `/model` choice is changed by sending `/model deepseek/deepseek-flash`
in that session, not by editing its files.

Three changes need no action, only knowing:

- **Claude cost after a process restart.** The first Claude turn after a
  session's process restarted (idle reclaim, daemon restart) used to report
  the session's lifetime cost and its most-used model as that one turn's, in
  the footer and in the usage ledger. Once a session has a saved baseline
  (written by any Claude turn after the upgrade), a resumed turn reports its
  own figures. An existing session's first resume without a saved baseline
  shows no cost and no model. Ledger records written before the upgrade keep
  their inflated values.
- **Claude Code's own auto memory is off** in the Claude sessions duoduo
  starts: duoduo disables it in the spawn environment, because that memory
  store would sit beside duoduo's memory as a second one. Nothing migrates.
  An `env` entry for `CLAUDE_CODE_DISABLE_AUTO_MEMORY` in a Claude settings
  file the session loads (for example the user-scope `~/.claude/settings.json`)
  still wins, so check there if auto memory is still active.
- **The bundled pi moves to 1.0.** Extensions are now judged against pi 1.0.
  A load error reaches the daemon log only at debug level and only when a pi
  worker is built: set `ALADUO_LOG_LEVEL=debug`, restart the daemon, send a
  message to a pi session, then look for `extension FAILED to load` in the
  log. Extension behaviour changes are in the caveats of `pi-runtime.md` in
  `duoduo-runtime-admin`.

## Changes landing in v0.8.5

**Check job `cwd_rel` values before upgrading.** Up to v0.8.4 a job whose
`cwd_rel` was an absolute path or pointed outside the work dir (possible
only in a job file edited by hand) ran silently in a system scratch
workspace, without its project `CLAUDE.md`. From v0.8.5 such a job fails
each run with `invalid cwd_rel path`. List the values and fix any that is
not a path inside the work dir:

```bash
grep -rn '^cwd_rel:' <runtime_dir>/var/jobs/active
```

Two changes need no action, only knowing:

- **Feishu process card no longer adds a `THINKING` reaction.** The working
  signal is an animated icon on the card's status line; reactions per turn
  are `Get`, then removed. Needs channel-feishu 0.8.5 and a channel
  stop + start (`duoduo upgrade` does both).
- **The bundled pi moves to 1.2.0, with its companion packages pinned.**
  This also fixes v0.8.4 installs whose pi runtime crashed on load. No
  settings changes; own pi extensions that handle `before_agent_start`
  should check pi 1.2.0's release notes.

## Changes landing in v0.8.9

**Check Feishu access policy before upgrading.** A missing
`FEISHU_DM_POLICY` or `FEISHU_GROUP_POLICY` now means `allowlist`, not
`open`. `FEISHU_BOT_OWNER` is always admitted in direct messages. In a
group, only chats in `FEISHU_ALLOW_GROUPS` and senders in
`FEISHU_ALLOW_FROM` get answers, unless `FEISHU_GROUP_POLICY=open` is
written explicitly. A named instance reads
only its own `feishu.<name>.env`, so check each one. Step 2's branch rules
already test for this; the gateway also logs the effective policy at
startup.

**On macOS, the restart moves the daemon behind the DuoDuo app.** When the
optional launcher package is installed, `duoduo upgrade` (or
`daemon restart`) reloads launchd, and privacy prompts name **DuoDuo**
instead of `node`. Grants made to `node` no longer apply to duoduo. An
owner who had granted `node` Full Disk Access and still wants it grants
DuoDuo once: `duoduo-runtime-admin` → "Full Disk Access on macOS".
`duoduo daemon status` shows the `launcher:` line. `daemon start` now
works over SSH; it fails only when nobody is logged in to the Mac's
desktop. Rollback: an older `duoduo` writes its old launchd entry on its
next start.

Three changes need no action, only knowing:

- **Claude Code telemetry and error reporting are off** in every Claude
  process duoduo starts (foreground, jobs, subconscious).
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY` and
  `DISABLE_ERROR_REPORTING` are set to `1` in the spawn environment. An
  `env` entry for the same key in a Claude settings file the session loads
  still wins.
- **An unrecognized model id now gets a 1M context window** in the bundled
  Claude Code (it was 200K). This matters for a non-Anthropic model run on
  the Claude runtime with no `claude.model_profiles` entry: if its real
  window is smaller, turns can fail at the limit before compaction runs.
  Add a profile with the real window (`duoduo-runtime-admin` →
  `references/model-context-profiles.md`). Profiled models are unaffected.
- **The bundled pi moves to 1.5.2, and its cache warming default is now
  `idle`.** Between runs, pi may re-send the last request to keep the
  provider's cache warm. duoduo keeps that default.

## Stdio output behavior in v0.5.3

The stdio terminal UI buffers assistant text more cleanly around status
and tool output. This is a user-interface fix: no migration is required,
and channel protocols do not change.

## Subconscious prompts are NOT auto-upgraded

A duoduo version upgrade installs new code. It does **not** change
the partition prompt files already present under
`<kernel>/subconscious/` on an existing installation. The install
logic merges missing files only — this deliberately preserves
local edits, agent self-programming, and user-authored partitions.

The consequence: if v0.5.1 ships a revised `pattern-tracker` prompt
and the user upgraded from v0.5.0, their `pattern-tracker/CLAUDE.md`
is still the v0.5.0 version after the upgrade.

### When to bring it up

Mention this explicitly when:

- Release notes for the target version mention subconscious /
  partition prompt changes.
- The user asks why their behavior looks the same after upgrading.
- The user asks how the subconscious partitions evolve between
  versions.

### How to refresh

Refreshing the subconscious is a separate, opt-in action. Each
published duoduo version has a matching `v<X.Y.Z>` tag on
`openduo/duoduo` that carries the reference `subconscious/` tree for
that version. Pulling that tree into the kernel is:

1. Fetch the target tag's `subconscious/` directory from the public
   repo.
2. Compare it to the kernel's current `subconscious/`.
3. Overwrite only the files that exist upstream (so user-authored
   partitions and local edits on unchanged files are untouched).
4. Commit the result in the kernel git repo, producing a clear
   rollback point.
5. Wait one cadence interval — prompts reload from disk each tick;
   no daemon restart needed.

The full decision guide and command shapes for each step — including
how to handle user edits to shipped partitions, what to do if the
target tag does not exist, and how to revert — live in
[`duoduo-runtime-admin/references/subconscious-refresh.md`](../../duoduo-runtime-admin/references/subconscious-refresh.md).

### When NOT to refresh

- The user never mentioned subconscious behavior and their release
  notes don't flag prompt changes. Stay silent; don't push a refresh
  they didn't ask for.
- The user has substantial self-programming in shipped partition
  files (not new partitions, but edits to ones that came from the
  public repo). Discuss the trade-off before overwriting.
- The kernel git tree is dirty. Ask the user to commit or stash
  first; refreshing on a dirty tree mixes unrelated changes into the
  refresh commit.

## Step 2.5 — Refresh these skills (they do NOT come with the upgrade)

The skills are published from the GitHub repo; the npm package does not
contain them. `npm install -g @openduo/duoduo` and `duoduo upgrade` both
leave them exactly as they were. An agent that upgraded the CLI and kept
its old skills is now operating a version it has stale instructions for
— which is the failure mode where an agent confidently uses a command
shape that no longer exists.

So whenever the CLI version changes, offer to refresh:

```bash
npx -y skills add https://github.com/openduo/duoduo --global --all
```

Notes that matter in practice:

- Add `</dev/null` when running non-interactively over SSH; the
  installer otherwise waits on a menu that never gets an answer.
- `--all` is the reliable shape. Selecting individual skills with
  `--skill <name>` can hang on the same interactive prompt.
- Skills land in `~/.agents/skills/`. A new session picks them up
  immediately — no daemon restart, no session restart.

This is opt-in, not automatic: say the version changed and ask. Do not
silently rewrite files under the user's home as part of an upgrade they
scoped to the daemon.

## Step 3 — Post-upgrade verification

Always verify:

```bash
duoduo --version                       # 0.5.x
duoduo daemon status                   # healthy: yes; version: 0.5.x
duoduo channel list                    # each channel shows 0.5.x versions
```

If a channel shows an older version than expected, restart that
channel explicitly:

```bash
duoduo channel <kind> stop
duoduo channel <kind> start
```

If the daemon reports an older version than expected, first check that
the install landed where the running binary lives — a `npm install -g`
against a different prefix is the usual cause, and `duoduo upgrade`
avoids it on builds that support it:

```bash
which duoduo                          # the binary actually in use
npm root -g                           # where a bare `npm install -g` writes
```

If those disagree, re-install with an explicit prefix (or use
`duoduo upgrade`), then restart:

```bash
duoduo daemon restart -r "reinstalled @openduo/duoduo into the right prefix"
```

If they agree, the install raced the restart; a second restart with a
reason is enough. Note that `restart` is stop+start only on hosts
without launchd — on macOS it asks launchd to replace the process,
which loads the new binary either way.

## Step 4 — If something goes wrong

Fall back to first-principles diagnosis:

- Daemon won't start: check `duoduo daemon logs` for the first
  stack trace.
- Restart or upgrade reports a health-check timeout: this is not by
  itself a failed upgrade, and the CLI cannot tell you which of the two
  causes it was. Check the real state (`duoduo daemon status`) before
  retrying anything. From v0.8.0 the daemon log separates them for you:
  shutting down waits for turns that are already running, and if a turn
  outlasts that wait the log says so and names the sessions it stopped
  waiting for. See that line and a session was mid-turn; see no such
  line and the daemon was simply slow to boot.
- Channel won't start: `duoduo channel <kind> logs`.
- Feishu-specific symptoms after upgrade: route to
  `duoduo-channel-admin` → `references/diagnose-feishu.md`.
- Accepted v0.5 limits (first-time group race, env typo unlock) are
  documented in `duoduo-channel-admin` →
  `references/feishu.md#accepted-v05-limits`.

The script is an accelerator. If it fails to run at all — sandbox
blocks it, missing bash features, PATH resolution issues — the agent
can still run every probe manually as shown in Step 1's fallback
section, and then follow the branch logic from there. Do NOT treat
the script as the only path.
