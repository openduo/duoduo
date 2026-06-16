# Pattern: Mechanical Layer + Brain Job

End-to-end guide for building a zero-idle-cost event pipeline on duoduo.

## When to use this pattern

- You have an external data source that needs periodic checking (feeds,
  APIs, files, webhooks).
- The source is quiet most of the time — new data arrives infrequently.
- You want the LLM to process new data promptly, but not burn tokens on
  empty polling rounds.
- A single cron job that runs the full LLM every tick would waste 90 %+
  of its budget on "nothing changed" checks.

## The two layers

### Mechanical layer (zero LLM)

A plain script — shell, Python, or any language — scheduled by launchd,
cron, or a systemd timer. Its only job is:

1. **Fetch** the current state from the source.
2. **Compare** against last-seen state (a local file, a seen-ids list, a
   timestamp cursor, …).
3. **If new data exists**: call `duoduo session notify` with the increment.
4. **If nothing new**: exit silently. The brain is never woken.
5. **If the source looks broken** (no updates for an unexpected period,
   HTTP errors, empty payload where content is expected): send a `STALE`
   alert message instead.

The script must not do any judgment, classification, or summarisation —
that is the brain's job. Keep it as a pure detector.

Example skeleton:

```bash
#!/usr/bin/env bash
SEEN_FILE="$HOME/.local/share/my-monitor/seen.json"
BRAIN_SESSION="job:my-monitor-brain.<hash>"

new_items=$(fetch_and_diff "$SEEN_FILE")   # your detection logic

if [ -z "$new_items" ]; then
  exit 0   # nothing new — brain stays dormant
fi

duoduo session notify "$BRAIN_SESSION" "New items: $new_items"
update_seen "$SEEN_FILE" "$new_items"
```

Schedule it with a launchd plist, a crontab entry, or a systemd timer
at whatever interval makes sense for your source (every 5 minutes, every
hour, etc.).

### Brain job (keepalive)

Create the brain as a duoduo job with `cron: keepalive`. A keepalive job
stays resident — it does not archive itself after a run, and it costs
nothing while dormant.

Minimal job frontmatter:

```yaml
---
type: job
cron: keepalive
runtime: codex   # or claude
cwd_rel: my-monitor   # working directory for state files
---
```

The brain's instruction body should describe:
- **On wake**: read the notify message for the incoming data increment.
  Process that data — do not re-fetch the full source; the mechanical
  layer already did the work and passed the increment in.
- **Classification / filtering**: decide which items meet the threshold
  for surfacing to the main session (see notify-routing.md).
- **State update**: write any persistent state (seen-ids list, summaries,
  logs) to local files before going dormant. The brain has no memory
  across wakes except what it writes to disk.
- **On STALE message**: forward a concise alert to the main session; do
  not attempt to re-fetch or diagnose. Then go dormant.
- **After handling**: stop. The job returns to dormant automatically when
  it finishes its run.

## Passing data through notify messages

The notify message body is the handoff channel between the mechanical
layer and the brain. Pack the increment into the message so the brain
does not need a second round-trip to the source:

- **Small increments** (a few items, short text): embed directly in the
  message body.
- **Large increments** (long documents, binary data): write to a temp
  file first; put the file path in the message body. The brain reads the
  file on wake.
- **Structured data**: a compact JSON string in the message body works
  well for id lists, metric readings, or key-value payloads.

The brain should treat the notify message as the authoritative increment
for that wake cycle. If the source has moved on by the time the brain
runs (a few more items appeared), that delta will arrive in the next
notify — do not re-poll to catch up within a single wake.

## Finding the brain job's session key

After creating the keepalive job, get its session key with:

```bash
duoduo session list --kind job
```

Use that key as the target for `duoduo session notify` in your mechanical
layer script.

## Comparison with `/loop`

| | `/loop` | mechanical-brain |
|---|---|---|
| Drive | Agent schedules its own next wake | External script triggers on event |
| Idle cost | Token spend every tick (ScheduleWakeup) | Zero — brain dormant between events |
| Latency | Bounded by chosen interval | Near-real-time (as fast as mechanical layer polls) |
| Best for | Active polling, self-paced tasks | Low-frequency external events |

Use `/loop` when the agent itself should decide when to check next. Use
this pattern when an external condition (new data, threshold crossing,
file change) should be the trigger.
