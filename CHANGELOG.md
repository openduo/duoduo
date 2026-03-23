# Changelog

All notable changes to this project will be documented here.

## [v0.3.5] - 2026-03-23

### Bug Fixes

- **cli**: Fix ESM self-invocation guard failing when install path contains spaces ([#11](https://github.com/openduo/duoduo/issues/11)). The CLI would silently exit with code 0 producing no output at all. Now uses `pathToFileURL()` for correct URL encoding.

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