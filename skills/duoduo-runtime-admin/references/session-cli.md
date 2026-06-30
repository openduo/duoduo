# Session CLI (`duoduo session …`)

Reference for the session-management subcommands. Load this when the user (or
you, the agent, on the user's behalf) wants to **name a session**, **list /
inspect sessions**, **wake another session by name**, **compact a session's
context**, or **archive a session**.

All are thin clients over the daemon's `/rpc`. They print **Markdown by
default** (human- and agent-readable) and accept **`--json`** for machine
parsing. Exit codes: `0` success, `2` refused / usage error, `1` hard error.

## Why sessions need names

A session_key is opaque (`lark:oc_…:…`, `job:…`, `stdio:…`). Without a name,
`list` and cross-session orchestration force you to copy keys around. Naming a
session writes a human label so the session is legible in `list`, on the
dashboard, and as a `notify` target. Unnamed sessions are NOT auto-labelled with
their key — they show `—` in `list` so "named vs not-yet-named" is obvious.

## `duoduo session list`

```
duoduo session list [--kind <channel|job|meta|subconscious|system>] [--named] [--all] [--json|--plain]
```

Lists every session the daemon knows. Columns: `ALIAS` (`—` if unnamed),
`SESSION_KEY`, `KIND`, `PLANE`, `LAST_EVENT`.

- `--kind <k>` — only sessions of that kind. `channel` = foreground (Feishu /
  stdio / ACP); `job` = scheduled jobs; `meta`/`subconscious`/`system` = kernel
  plane (you usually don't touch these).
- `--named` — only sessions that have an alias set.
- `--all` (alias `--include-orphans`) — also show **orphan** job sessions.
- `--json` — array of structured rows (use this when parsing in a script).

By default the list **hides orphan job sessions** so it agrees with
`ManageJob(list)`. An orphan is a `job:` session whose owning job is no longer
in the active set — typically a job that was recreated with a changed schedule
or workspace (its session key gets a new hash and the old one lingers), or a job
whose definition was deleted. These linger in the index but aren't live work, so
they're noise in the default view. Pass `--all` to see them; with `--all` an
orphan row is marked `job (orphan)` (and `orphan: true` in `--json`).

This IS the live route table — prefer it over any hand-maintained id↔name map.

## `duoduo session alias`

```
duoduo session alias <session_key> "<name>"     # set a name
duoduo session alias <session_key> --clear       # unset, back to —
duoduo session alias <session_key>               # show current name
```

Sets a human label on a session (stored in the session's `meta.md`). The name is
free text; quote it if it has spaces. A name with YAML-special characters
(`:`, quotes) is stored safely.

Typical use: the user says "name this session X" / "把这个会话叫 X" → resolve
the current session_key (the user's session, or one from `list`) → run
`alias <key> "X"`.

Returns `not_found` (exit 2) if the session_key doesn't exist. Note: a session
that exists but has no `meta.md` yet can't be named until it has run at least
once — `set_alias` failing does NOT remove it from `list`.

## `duoduo session notify`

```
duoduo session notify <target> -m "<message>" [--source <label>]
```

Wakes a session and delivers a message to it. `<target>` is a **session_key OR a
display-name alias** (so `notify "Journal" -m "…"` works once Journal is named).

The message arrives as a **source-tagged notification**, not a user message —
the woken session decides for itself whether to act on it (it will not blindly
execute the text). `--source <label>` tags where the notify came from (defaults
to `session.notify`); use it so the receiver knows the origin (e.g.
`--source ci`).

**Isolation boundary — only `channel` and `job` sessions can be notified.** A
target that resolves to a `meta` / `subconscious` / `system` session is refused
with `forbidden_kind` (exit 2). The subconscious and kernel plane run on their
own cadence and must never receive an externally-injected, unscheduled turn.

Other refusals (all exit 2, no delivery): `ambiguous` (the alias matches more
than one session — the candidates are listed; re-run with a specific
session_key), `not_found` (no session by that key or name).

Use this to orchestrate across sessions — e.g. a monitoring job that finds
something notifies a longer-lived research session to dig in, or an external
script / webhook (`ssh host 'duoduo session notify "主控台" -m "…"'`) pokes a
live session. It is the programmatic, by-name version of the in-session `Notify`
tool.

## `duoduo session compact`

```
duoduo session compact <target> [--source <label>] [--json|--plain]
```

Queues a `/compact` for a channel session — shrinks its resident conversation
context the same way the in-chat `/compact` command does. `<target>` is a
**session_key OR a display-name alias**.

**Channel sessions only.** `job` / `system` / `subconscious` targets are refused
— they run a fresh query per drain and hold no resident context to compact.

**Fire-and-forget.** `/compact` is queued and runs on the session's **next
turn**; this call returns no token delta. The compaction acknowledgement
(`📦` / "Nothing to compact") lands in the **target** session's outbox, not in
this command's output. So an agent running `compact` should not expect a
post-compact token count back — it only gets "queued" confirmation.

Use it to pre-empt context bloat on a long-lived channel session (e.g. an owner
DM that has accumulated a large history) without waiting for the session to hit
its own auto-compact threshold.

## `duoduo session archive`

```
duoduo session archive <session_key>
```

Moves the session's artifacts into `var/<kind>-archive/` — nothing is deleted.
Recover by `mv`-ing the archived directory back. Refuses while an actor is live
(`active`, exit 2) — cancel the running turn first. Archive does NOT cancel a
running turn; it only moves files.

## Output discipline (for agents)

When you run these via Bash and need to act on the result, pass `--json` and
parse it — do not screen-scrape the Markdown table. The Markdown form is for
the human reading the terminal.
