# Notify Routing and Signal Filtering

How the brain job decides what to surface, how to format outbound briefs,
and how to route them to the right session without flooding your chat.

## The brain is a filter, not a relay

The mechanical layer already filtered out empty rounds. The brain's job is
a second, semantic filter: of the new data that arrived, which items
actually warrant waking the main session?

The mechanical layer answers "is there anything new?" (binary).  
The brain answers "is any of it worth the user's attention?" (graded).

Default two-tier model — adapt to your domain:

| Tier | Description | Action |
|---|---|---|
| **P0 / P1** | High-signal items meeting your threshold | Send a Notify brief to main session |
| **P2 / Noise** | Low-signal, routine, or marginal items | Update local state files only; go dormant silently |

The exact threshold is yours to define. A price monitor might set P0 as
"moved more than 5 % in one hour". A feed monitor might set P0/P1 as
"posted by a tracked account and matches one of my topic keywords".

**Prefer under-notifying over over-notifying.** A main session that
receives a brief every waking cycle quickly becomes noise. Reserve Notify
for items that genuinely need a human decision or awareness.

## Notify message format

When the brain decides to surface a signal, send one consolidated brief
per wake cycle — never one message per item.

Recommended structure:

```
[Monitor name — brief subject line]

BLUF: one-sentence summary of what was found and why it matters.

Signals this batch:
- <time> · <source/item> · <one-line summary> · <tier>
- <time> · <source/item> · <one-line summary> · <tier>

Cross-checks: [any corroboration done, or "none"]

Suggested action: [what you think the user should do, or "review"]
```

Keep the brief compact. The user should be able to read it in under
30 seconds and decide whether to dig in.

## Routing rules

**Hard-code the target session key.** The brain must not discover,
guess, or select the destination dynamically. Write the target session
key directly in the job's instruction body:

```
Notify target: lark:<channel-id>:<user-id>:<session-hash>
```

Get this key from `duoduo session list` or from the session's own `CLAUDE.md`.

**If Notify returns a candidate list**: stop immediately. Do not
self-select from the list, do not retry with a different key, do not
fall back to another session. Write a note to the local state log and go
dormant. Mis-routing a brief to the wrong session is worse than missing
a round.

**If no signal clears the threshold**: do not send a Notify at all. Update
local state silently and return dormant. The main session should never
receive "nothing to report this cycle" messages.

## STALE handling

When the mechanical layer detects that the upstream source has stopped
updating unexpectedly (no new data for longer than the expected cadence,
repeated errors, or an explicitly empty payload), it sends a STALE
message instead of a normal notify.

The brain's response to a STALE message is intentionally minimal:

1. Forward a one-line alert to the main session:
   > `[Monitor name] Data source appears stale — no updates since <last
   > seen time>. Upstream may be down or the source format may have
   > changed. Manual check recommended.`
2. Do not attempt to re-fetch, diagnose, or recover. That requires a
   human decision.
3. Go dormant. The mechanical layer will send another STALE on its next
   cycle if the problem persists, or a normal notify when data resumes.

## State files

The brain has no memory across wakes except what it writes to disk. Keep
a minimal set of state files in the job's working directory:

- **`state/seen.json`** (or similar) — ids or timestamps of items already
  processed, to avoid re-surfacing on the next wake.
- **`state/signal-log.md`** — a running log of what each wake found and
  what action was taken. Useful for debugging and for giving context to
  the main session on request.

Update state files before going dormant. If the brain crashes mid-run,
an incomplete state update is less harmful than a duplicate Notify on the
next wake — so write the "processed" marker only after the Notify is sent
(or after the silent-discard decision is made).
