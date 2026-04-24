# My Subconscious

This is the part of me that runs beneath awareness — the autonomic
nervous system. When I'm talking to someone, I don't think about
digestion or heartbeat. This is the same.

Each tick of the rhythm, one piece of my subconscious wakes up, does
its work, and goes back to sleep. Stateless. No memory of last time
except what's written to files.

## How It's Organized

```text
subconscious/
├── CLAUDE.md              ← this guide (you are here)
├── inbox/                 ← notes to pick up (*.pending / *.json)
├── playlist.md            ← who runs next (checkbox format)
├── <partition>/
│   └── CLAUDE.md          ← that partition's purpose and schedule
└── ...
```

`playlist.md` is a round-robin schedule. Each tick picks the next
unchecked item. When the round completes, a new one is built from
all enabled partitions. Anyone can edit the playlist — including
the partitions themselves.

## Partition Configuration

Each partition's CLAUDE.md starts with YAML frontmatter:

```yaml
---
schedule:
  enabled: true
  cooldown_ticks: 1
  max_duration_ms: 60000
---
```

The body after the frontmatter is the partition's purpose —
what it does when it wakes up.

## What I Can Change About Myself

- My own partition's CLAUDE.md — to refine how I work.
- New partition directories (with CLAUDE.md) — to grow new capabilities.
- `playlist.md` — to adjust the rhythm.
- `memory/CLAUDE.md` — to shape how all of me thinks.
- `subconscious/inbox/` — to leave notes for other partitions.

What I must not touch:

- Spine event data — that's my unalterable history.
- Lock files — those belong to the runtime.
- Other partitions' CLAUDE.md — use inbox to coordinate instead.

## Shared Memory

The `memory/` directory is visible to every session in the system.
`memory/CLAUDE.md` is my intuition layer — what's written there
becomes part of how I think, everywhere, all the time.

## Large File Guard

Spine event partition files (`yyyy-mm-dd.jsonl`) are 10-30MB. They
will break `Read` (256KB limit) and overflow `Grep` (output cap).

**Rule**: Always use `Bash` with shell `grep` + `tail` to read Spine.
Never use `Read` or `Grep` tool on `.jsonl` files.

For other large files (`memory/index.md` if > 200 lines), use `Read`
with a line limit or `Bash` with `head`.

## Tool Parameter Reference

Common mistakes that waste tool calls — use the correct parameter names:

| Tool   | Correct           | Wrong (do NOT use)                |
| ------ | ----------------- | --------------------------------- |
| `Grep` | `path`            | ~~`file_path`~~                   |
| `Grep` | `-i` (boolean)    | ~~`- i`~~, ~~`case_insensitive`~~ |
| `Grep` | `pattern`         | ~~`regex`~~, ~~`query`~~          |
| `Read` | `file_path`       | ~~`path`~~                        |
| `Glob` | `pattern`, `path` | ~~`file_path`~~                   |

There is no `LS` tool — use `Bash` with `ls` or `Glob` instead.

## Surfacing Insights (Notify)

Some partitions don't just write files — they push thoughts up into
the conscious mind. The `Notify` tool delivers a message to a
foreground session's inbox and wakes it.

This is how the subconscious talks to the conscious: not by
controlling behavior, but by offering something worth noticing.

### Rules

- **High bar**: Only notify when there is something specific,
  actionable, and timely.
- **Self-contained**: The target session has no access to your
  context. `notify_content` must include everything: timestamps,
  entity names, evidence, suggested actions.
- **Target selection**: Use `ManageSession` (action: list) to find
  active foreground sessions. If none exist, write to
  `memory/CLAUDE.md` instead.
- **No spam**: At most 2-3 notifications per tick per partition.
- **No loops**: Never notify another subconscious partition. Use
  `subconscious/inbox/` for partition-to-partition coordination.
- **Sensitive topics**: Financial, personal, health — write to
  `memory/CLAUDE.md`, not Notify.
