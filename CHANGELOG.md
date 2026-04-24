# Changelog

All notable changes to this project will be documented here.

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