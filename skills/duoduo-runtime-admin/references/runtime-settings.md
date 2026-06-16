# Runtime Settings

Use this reference when editing persistent host-mode settings.

## Primary Inspection Commands

```bash
duoduo daemon status
duoduo daemon config
duoduo daemon logs          # tails the last N lines by default
duoduo daemon logs --lines 500   # show more
duoduo daemon logs --all         # full log (can be large)
```

`duoduo daemon logs` shows the **tail** by default (like `tail` / `docker
logs`), so it stays readable when run via Bash; pass `--lines N` for more or
`--all` for the whole file.

To check whether the installed CLI is behind npm:

```bash
duoduo --version
npm view @openduo/duoduo version
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
- `ALADUO_DEFAULT_RUNTIME` (`claude` or `codex`): global fallback for actors
  without a more-specific runtime declaration. Use a channel kind descriptor
  when only one surface should change.
- `ALADUO_CODEX_SANDBOX` (codex is auto-detected from v0.5; there is
  no enable flag. See [codex-runtime.md](codex-runtime.md).)
- `CLAUDE_CODE_EXECUTABLE`: explicit Claude Code runtime override for
  the daemon. Use this when the SDK optional native binary did not install
  but a compatible local `claude` executable is available. Prefer an absolute
  path. After editing it, restart the daemon.

## Experimental Flags (default OFF — opt in per host)

These gate not-yet-default capabilities. All default OFF; set them in
`~/.config/duoduo/.env` only when you intend to run the experiment. They are
**not** standard tuning knobs.

- `ALADUO_EXP_FEISHU_CARD_FOOTER`: render a one-line ops footer
  (`elapsed · tokens · cost`, or `elapsed · N steps` on a Codex turn) on the
  finalized Feishu streaming card. **Read by the Feishu channel process, not
  the daemon** — after setting it, restart the channel
  (`duoduo channel feishu stop && duoduo channel feishu start`), a daemon
  restart alone does not pick it up. Confirm it landed with
  `ps eww <feishu-pid> | tr ' ' '\n' | grep ALADUO_EXP_FEISHU_CARD_FOOTER`.
- `ALADUO_EXP_MEMORY_CHECK`: run the mechanical memory lint (board/entity/node
  measure + orphan/island notify) as a pre-step on every cadence tick. It only
  ever writes slug-named `.pending` notes into partition inboxes — reversible,
  no data loss.
- `ALADUO_EXP_MEMORY_FORGET`: **destructive.** Lets the lint `git rm` memory
  nodes that are board-unreachable, ≥48h old, and have zero inbound links.
  Git-recoverable (memory is a subdir of the kernel git repo), but it deletes
  files. Depends on `ALADUO_EXP_MEMORY_CHECK` also being on.

The `duoduo memory` CLI subcommand gives operators and subconscious
partitions direct access to the same lint primitives: `check` posts
signals to partition inboxes on demand, individual `board-lint` /
`entity-lint` / `node-lint` subcommands inspect one area at a time,
and `reclaim` handles the destructive orphan-deletion lifecycle
(requires `--tag`; supports `--dry-run`). See
[memory-cli.md](memory-cli.md) for the full command reference.

> **Version coupling — refresh the subconscious before enabling the MEMORY
> flags.** The lint emits `.pending` notes whose format is parsed by the
> subconscious partition prompts (pattern-tracker / memory-weaver). They are
> version-coupled: an older partition set will mis-parse or ignore a newer
> lint's signals. Before turning on `ALADUO_EXP_MEMORY_CHECK` /
> `ALADUO_EXP_MEMORY_FORGET`, refresh this host's subconscious partitions to
> the matching duoduo tag (see the subconscious-refresh reference under this
> skill). The Feishu footer flag has no such dependency.

Confirm any of these landed with `duoduo daemon status`, which now reports the
`memory_check` flag state (and cadence / subconscious progress) — the reliable
check, since the host daemon's env is not visible via `ps`.

## Practical Rules

- Use `duoduo daemon config` to confirm the current effective values.
- Use daemon restart after changing env-backed runtime settings.
- Use daemon restart after updating `@openduo/duoduo` itself with npm.
- Use channel restarts separately when only plugin process env changed.
