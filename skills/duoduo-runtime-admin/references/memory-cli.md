# Memory CLI (`duoduo memory`)

Use this reference when an operator wants to inspect or maintain the
memory tree manually, or when a subconscious partition invokes memory
maintenance via Bash.

`duoduo memory` is the mechanical (no-LLM) half of memory maintenance.
It measures the memory tree and routes convergence signals into
partition inboxes as `.pending` files; the intelligent partitions
(pattern-tracker / memory-weaver) process those signals on their own
cadence ticks.

## Subcommands

### `duoduo memory check [--dry-run] [--limit=N] [--json|--plain]`

The default automation path. Runs all the mechanical lints — board, entity,
node, the orphan island report, **and gap-lint** — and posts the
worst-finding(s) as `.pending` signals into the relevant partition inboxes.

- `--dry-run`: measure only, no inbox writes. Safe to run at any time.
- `--limit=N`: how many signals to post per lint class (default 1).
- Never deletes memory data. All writes are reversible `.pending` files.

**gap-lint** is the program half of "gap-driven dreaming": it scans the event
log against the existing memory fragments, finds a day with events but no
fragments written for it, and posts a bounded `scan-gap.md.pending` interval to
the memory-weaver inbox. This replaces the weaver self-selecting what to dream
about (an unbounded scan that could time out producing zero fragments) with a
program-computed, one-bounded-day-per-tick target. The `check` output reports a
`gap:` line — either the chosen day, or `none — all external days dreamt`.

This is what the daemon calls automatically on every cadence tick when
`ALADUO_EXP_MEMORY_CHECK` is enabled (or when the partition `CLAUDE.md`
carries a valid `contract:` declaration — see the
[subconscious-refresh reference](subconscious-refresh.md)).

### `duoduo memory board-lint [--notify] [--limit=N] [--json|--plain]`
### `duoduo memory entity-lint [--notify] [--limit=N] [--json|--plain]`
### `duoduo memory node-lint [--notify] [--limit=N] [--json|--plain]`

Single-lint inspect path. Read-only report by default; `--notify` opts
in to posting the worst finding into the relevant inbox.

These are the "inspect one thing" counterparts to `check` (which runs
all three and notifies by default). Use them when you want to see what
a specific lint class finds without triggering inbox writes.

### `duoduo memory reclaim --tag=<id> [--dry-run] [--json|--plain]`

Manual, destructive orphan lifecycle. `--tag` is mandatory — it forces
an explicit recorded intent so the operation is auditable.

What it does:

- **Newborn orphans** (recently created, not yet on the board): receive
  an idempotent warning `.pending` in the weaver inbox.
- **Islands** (board-unreachable clusters): receive a weaver inbox note
  summarizing the cluster.
- **Stale orphans** (board-unreachable, age ≥ 48h, zero inbound links):
  deleted via `git rm`. Git-recoverable from the kernel git history.

`--dry-run` reports what would happen without deleting anything.

`reclaim` is **never** triggered automatically by `check`. It is always
a manual operator decision.

## Write-Danger Classification

| Class | Who runs it | Writes what | Reversible |
| --- | --- | --- | --- |
| A | `check` (auto + manual) | `.pending` inbox signals | Yes — delete the file |
| B | `check` (summary only) | Nothing posted | N/A |
| C | `reclaim` (manual only) | `git rm` stale nodes | Yes — `git revert` |

## Environment Flags

- `ALADUO_EXP_MEMORY_CHECK`: when set (and no partition `contract:` block
  overrides it), the daemon runs `duoduo memory check` automatically before
  each cadence tick. Omit for manual-only operation.
- `ALADUO_EXP_MEMORY_FORGET`: enables the destructive delete path inside the
  automatic cadence-driven check. Has no effect on the manual `reclaim`
  subcommand (that path is always available regardless of this flag).
  Requires `ALADUO_EXP_MEMORY_CHECK` to also be on.

See [runtime-settings.md](runtime-settings.md) for the version-coupling
note: enabling these flags before refreshing the subconscious partitions
to a matching version may cause signals to be mis-parsed or ignored.

## Usage Patterns

**Operator: inspect without side effects**

```bash
duoduo memory check --dry-run
duoduo memory board-lint
```

**Operator: manual signal post for one lint class**

```bash
duoduo memory node-lint --notify --limit=3
```

**Operator: orphan cleanup (preview first)**

```bash
duoduo memory reclaim --tag=cleanup-2026-06 --dry-run
duoduo memory reclaim --tag=cleanup-2026-06
```

**Subconscious partition (via Bash in a partition turn)**

```bash
duoduo memory check
duoduo memory board-lint --notify
```

The command is intentionally hidden from `duoduo --help` (it is an
advanced maintenance surface). Run `duoduo memory --help` to see the
current subcommand list on the installed version.
