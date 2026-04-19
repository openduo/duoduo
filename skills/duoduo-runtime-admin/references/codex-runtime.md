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

## Host-Mode Gate (v0.5+)

Codex is **auto-detected** from v0.5 onward. There is no
`ALADUO_CODEX_ENABLED` env var anymore. If `codex` is installed on
`PATH` and `codex login status` reports "logged in", the daemon
advertises `runtime: "codex"` on ManageJob and accepts it in job
definitions. Otherwise codex is hidden entirely and any
`runtime: "codex"` request falls back to Claude silently.

Optional persistent key:

- `ALADUO_CODEX_SANDBOX=workspace-write` (or `read-only` /
  `danger-full-access`) — sandbox mode for codex-runtime jobs.

The daemon probes at boot. If the user installs codex or runs
`codex login` while the daemon is running, ask them to restart:

```bash
duoduo daemon restart
```

If the daemon seems not to see a freshly-logged-in codex, check with
`codex login status` directly to confirm the CLI side.

## Scope

Current scope is narrow:

- Codex is an optional job runtime backend.
- Foreground channel sessions remain Claude-first unless the runtime version
  being inspected proves otherwise.

Do not oversell this as a universal runtime switch.
