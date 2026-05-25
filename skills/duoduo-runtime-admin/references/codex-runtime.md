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

## Host-Mode Availability (v0.5.3+)

Codex is **auto-detected**. There is no `ALADUO_CODEX_ENABLED` env
var. If `codex` is installed on `PATH` and `codex login status`
reports "logged in", the daemon exposes Codex as an available runtime
alongside Claude. Otherwise Codex is hidden from runtime choices and
runtime requests fall back to Claude.

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

## Runtime Selection

Duoduo picks a runtime by specificity:

1. Actor-level declaration, such as a channel descriptor, job frontmatter, or
   partition frontmatter.
2. Channel-kind default in `kernel/config/<kind>.md`.
3. Global default, usually `ALADUO_DEFAULT_RUNTIME=codex`.
4. Conservative fallback: `claude`.

Use `ALADUO_DEFAULT_RUNTIME=codex` only when the operator wants all actors
without a more-specific declaration to prefer Codex. For one channel kind,
edit that kind descriptor instead; for one channel instance, edit or re-run the
channel setup flow for that instance.

## Scope

Codex is now a peer runtime for channel sessions, jobs, and eligible background
partitions. Claude remains the default fallback and the safer recommendation
when the user has not explicitly asked to route work to Codex.

Do not claim existing sessions hot-swap immediately after changing defaults.
For a live channel, check its descriptor and session state, then rebind/archive
when the user wants a clean runtime switch.

## Caveats

- Codex project trust is local to the machine. Multi-host deployments need
  `codex login` and project trust on each host that will run Codex work.
- `workspace-write` sandbox blocks network access, including localhost. Use
  `ALADUO_CODEX_SANDBOX=danger-full-access` only when the user explicitly needs
  networked commands from Codex.
- Codex does not honor Claude-style tool allow/deny lists exactly. Treat tool
  restrictions as instructions, not hard enforcement, when the selected runtime
  is Codex.
