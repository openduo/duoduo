# Runtime Settings

Use this reference when editing persistent host-mode settings.

## Primary Inspection Commands

```bash
duoduo daemon status
duoduo daemon config
duoduo daemon logs
```

## Persistent File

```bash
~/.config/duoduo/.env
```

This file is the persistent host-mode env surface. Changes here usually require:

```bash
duoduo daemon restart
```

The restart is not optional when the change targets daemon env-backed behavior:
the host daemon is already running in the background and does not hot-reload its
binary or env from your shell.

## Common Keys

- `ALADUO_LOG_LEVEL`
- `ALADUO_LOG_RUNNER_THOUGHT_CHUNKS`
- `ALADUO_LOG_SESSION_LIFECYCLE`
- `ALADUO_TELEMETRY_ENABLED`
- `ALADUO_CADENCE_INTERVAL_MS`
- `ALADUO_CODEX_ENABLED`
- `ALADUO_CODEX_SANDBOX`

## Practical Rules

- Use `duoduo daemon config` to confirm the current effective values.
- Use daemon restart after changing env-backed runtime settings.
- Use daemon restart after updating `@openduo/duoduo` itself with npm.
- Use channel restarts separately when only plugin process env changed.
