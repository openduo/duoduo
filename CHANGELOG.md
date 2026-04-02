# Changelog

All notable changes to this project will be documented here.

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