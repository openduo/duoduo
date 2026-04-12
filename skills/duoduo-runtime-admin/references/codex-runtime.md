# Codex Runtime

Use this reference before enabling or explaining Codex support.

## Prerequisites

- `codex` CLI installed and on `PATH`
- `codex` authenticated on this machine

Useful checks:

```bash
codex --version
codex login
```

## Host-Mode Gate

Persistent keys:

- `ALADUO_CODEX_ENABLED=1`
- optional `ALADUO_CODEX_SANDBOX=workspace-write`

These belong in `~/.config/duoduo/.env` and usually require:

```bash
duoduo daemon restart
```

## Scope

Current scope is narrow:

- Codex is an optional job runtime backend.
- Foreground channel sessions remain Claude-first unless the runtime version
  being inspected proves otherwise.

Do not oversell this as a universal runtime switch.
