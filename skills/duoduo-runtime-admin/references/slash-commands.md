# Slash Commands (`/compact`, `/undo`)

Reference for the chat-level history controls that landed in v0.5.2.
Load this when the user asks about compacting a long conversation,
undoing the last turn, or these commands appearing not to work.

## Commands

Both commands are user-typed text in a channel session (Feishu DM,
stdio CLI, ACP editor — anywhere a session accepts messages). They
flow through the same spine → mailbox → drain pipeline as normal
messages, so the user gets a regular text reply when the command
finishes.

### `/compact`

Compacts the conversation history in place. Keeps the same session
id; both runtimes shrink the context window by summarizing earlier
turns into a single compact boundary.

- **Claude runtime**: emits a `compact_boundary` system message; the
  session continues with the same `sdk_session_id`.
- **Codex runtime**: calls `thread/compact/start` natively; the
  session continues with the same `threadId`.

User-visible reply: a short confirmation that compaction happened.
The next turn the user sends will run against the compacted history.

### `/undo` and `/undo N`

Removes the last `N` exchanges from the conversation. Defaults to
`/undo 1` if no number is given.

- **Codex runtime**: synchronous — calls `thread/rollback` inside the
  drain that processed the `/undo` message.
- **Claude runtime**: deferred — sets a `pending_undo` state field;
  the actual `forkSession` call happens on the next user-message
  turn. From the user's perspective this is invisible: they type
  `/undo`, get a confirmation, then type their next message and the
  reply reflects the rolled-back state.

The deferred behavior on Claude is intentional. Claude has no
in-place rewind primitive; using `forkSession` immediately would
produce a fresh `sdk_session_id` that needs to be written from
outside the normal turn-finalize path. Deferring keeps the
"`sdk_session_id` is written only by a real turn" invariant intact.

## What to tell the user when something looks off

**"I typed `/compact` but nothing happened."** — Check that the
session is on v0.5.2 or later (`duoduo daemon status` reports the
running version). On versions before v0.5.2, the Claude SDK silently
ate `/compact` (compaction did run, but the gateway never surfaced
the boundary as a reply); on Codex, it was treated as plain text and
ignored. v0.5.2 fixes both.

**"`/undo` on Claude didn't seem to roll back."** — The rollback
materializes on the *next* user message. If the user types `/undo`
and then immediately reads `duoduo session list`, they will see the
pending_undo flag still set; it clears when the next real turn
finalizes. This is the deferred-fork design, not a bug.

**"The reply landed in the wrong session."** — Both commands route
through the same channel mailbox as normal messages, so if a Feishu
DM is bound to session A, `/compact` and `/undo` apply to A. If the
user expected B, the channel is on the wrong binding — that is a
channel-binding question, not a slash-command question.

**Feishu groups + `/compact`**: in a multi-principal group, `/compact`
applies to the session bound to that chat_id. There is no per-user
compact; the whole group sees the same compacted history when the
next message arrives.

## Cross-runtime cheat sheet

| Behavior | Claude | Codex |
| --- | --- | --- |
| `/compact` execution | inline, SDK-side | inline, `thread/compact/start` |
| `/compact` session id change | none (`sdk_session_id` unchanged) | none (`threadId` unchanged) |
| `/undo` execution | deferred to next turn (`pending_undo`) | inline, `thread/rollback` |
| `/undo` session id change | new `sdk_session_id` on next turn | none (same `threadId`) |

## Design rationale

See `docs/design/conversation-history-controls.md` in the source
repo for the full architectural decisions (Qa-Qe). The short version:
spine + mailbox is aladuo's only control plane, so slash commands
must flow through it like any other channel input — no second queue.

## When this skill does NOT apply

- `/clear` and `/cancel` — those are interrupt-now semantics and
  bypass the drain loop. Different runtime path; this skill does
  not cover them.
- Custom slash commands that an operator wires into their own
  channel — out of scope.
