# Usage Ledger Archive

Use this reference when the operator wants to **clean up the usage ledger**
(e.g. "归档老的 usage", "保留最近 N 周", "缩 var/usage", "the ledger is too
big"). It explains layout, the safe-to-archive rule, and the verified
move recipe.

duoduo never archives usage automatically — there is no built-in retention
policy. Every drain across every session has been appending to disk since
day one, so on long-lived hosts `~/.aladuo/var/usage/` accumulates to
hundreds of megabytes.

## Storage Layout

```
~/.aladuo/var/
  usage/
    <session_key_escaped>.jsonl    one append-only file per session
  usage-archive/                   archive root, sibling of usage/
    <YYYY-MM-DD>/                  one bucket per archive run
    legacy.<YYYY-MM-DD>/           any pre-existing archive subdirs swept here
```

Two structural rules to know before touching anything:

1. **The daemon scans only the top level of `usage/`** and ignores files
   that don't end in `.jsonl` — so any subdirectory inside `usage/`
   (including a stray `usage/archive/`) is silently skipped, not read.
   That makes the archive sibling pattern safe.
2. **The archive sibling is `usage-archive/`, NOT `usage/archive/`.**
   This mirrors `var/sessions-archive/` (sibling of `var/sessions/`)
   and keeps the archive out of the daemon's scan path even if a future
   change starts recursing.

## What Counts As "Old"

Use **file mtime**, not the `drain_started_at` timestamp inside JSON
records. mtime tracks the last append, so:

- A session that first ran 60 days ago but is still draining today —
  mtime is fresh, file stays. Correct.
- A session that died 30 days ago — mtime is 30 days old, file moves.
  Correct.
- A 30-day-old session that fires once today — its file is recreated by
  `appendDrainRecord` (it uses `fs.appendFile` which opens by path);
  the archived file keeps its history, the new file starts fresh. No
  data loss, just a small statistical discontinuity for that session.

A 14-day window is the working default. Adjust by changing `-mtime +14`.

## Recipe (Verified Against tracy-mini-m4 On 2026-04-28)

The daemon does **not** need to be stopped. `appendDrainRecord` only
touches files whose mtime is by definition recent, so it never collides
with the mv targets. (See "Race Note" below for the one edge case.)

```bash
# Run on the host (over ssh as the duoduo user)
ssh <host> 'cd /Users/<user>/.aladuo/var && \
  TS=$(date +%Y-%m-%d) && \
  mkdir -p usage-archive/$TS && \
  echo "before: $(find usage -maxdepth 1 -name "*.jsonl" -type f | wc -l) total, $(find usage -maxdepth 1 -name "*.jsonl" -type f -mtime +14 | wc -l) stale" && \
  find usage -maxdepth 1 -name "*.jsonl" -type f -mtime +14 -print0 \
    | xargs -0 -I{} mv {} usage-archive/$TS/ && \
  echo "moved $(ls usage-archive/$TS/ | wc -l | tr -d " ") files" && \
  if [ -d usage/archive ]; then \
    mv usage/archive usage-archive/legacy.$TS && \
    echo "swept legacy usage/archive → usage-archive/legacy.$TS"; \
  fi'
```

Key flags:

- `-maxdepth 1` — only top-level files, never recurse into archive
  subdirectories.
- `-name "*.jsonl"` — only ledger files, never `DUODUO.md` or other
  sibling artifacts in `usage/`.
- `-type f` — exclude any directory entries.
- `-print0 | xargs -0` — handle filenames with colons/spaces safely
  (session keys contain `:`).

## Verification

After the move:

```bash
ssh <host> 'cd /Users/<user>/.aladuo/var && \
  echo "active jsonl: $(find usage -maxdepth 1 -name "*.jsonl" -type f | wc -l)" && \
  echo "stale remaining (must be 0): $(find usage -maxdepth 1 -name "*.jsonl" -type f -mtime +14 | wc -l)" && \
  echo "archived today: $(find usage-archive/$(date +%Y-%m-%d) -type f | wc -l)" && \
  du -sh usage/ usage-archive/'
```

Then confirm the daemon still serves usage:

```bash
ssh <host> 'source ~/.zshrc && duoduo daemon status | head -3'
ssh <host> 'curl -s -X POST http://127.0.0.1:20233/rpc \
  -H "content-type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"usage.get\",\"params\":{}}" \
  | head -c 200'
```

The daemon does not need a restart — it does not cache the usage list;
the next `usage.get` call re-reads the directory.

## Recovery

The archive is recoverable; nothing is deleted.

```bash
# Restore one specific session
ssh <host> 'mv ~/.aladuo/var/usage-archive/<bucket>/<session_key>.jsonl \
            ~/.aladuo/var/usage/'

# Restore an entire archive bucket
ssh <host> 'mv ~/.aladuo/var/usage-archive/<bucket>/*.jsonl \
            ~/.aladuo/var/usage/'
```

To truly free space, the operator deletes the archive directory by
hand once they are sure they don't need the records:

```bash
ssh <host> 'rm -rf ~/.aladuo/var/usage-archive/<bucket>/'
```

## Race Note

There is a real but tiny race window:

- `find` listed file X (mtime 14d+1s).
- A new drain on session X fires before `mv` reaches it.
- `appendDrainRecord` calls `fs.appendFile` with the original path.
- `mv` moves the file, then `fs.appendFile` recreates it under the
  original path with just the new line.

Net effect: the historical lines for session X end up in
`usage-archive/<bucket>/`, the new line(s) end up in a freshly created
`usage/<key>.jsonl`. No crash, no data loss — just a per-session split.
Acceptable for a maintenance operation.

If the operator wants zero risk of split-history files, stop the daemon
before archiving:

```bash
duoduo daemon stop
# ... do the mv ...
duoduo daemon start
```

But this is optional and uncommon.

## Related Behavior — Session Archive

`session.archive` (the `duoduo session archive <session_key>` command)
**does not** also archive that session's usage file. The two archive
flows are independent. If the operator's intent is "remove this
session's footprint completely", point out that they would also need
to manually move `var/usage/<session_key>.jsonl` if they want it gone
from the live ledger.

This is by design — usage is a statistical record and outlives the
session that produced it.
