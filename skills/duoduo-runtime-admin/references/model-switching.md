# Model Switching (`/model`)

Use this reference when the user wants to switch the model for a running
session, list available models, or recover from an invalid model id.

## Commands

```
/model                    # show current model + available models
/model <model-id>         # switch to a specific model
/model reset              # revert to the daemon's default model
```

All three forms flow through the normal channel message pipeline —
they are typed as a chat message, not a CLI call.

## Claude Runtime

`/model` with no args shows:

- The currently stored model override (or `(runtime default)` if none).
- A list of known model ids populated from the live session.

The list only appears after the session has processed at least one
message. If the session has not started yet, `/model` notes this and
tells the user to send a message first. The list is a convenience
menu — valid model ids not on it are also accepted.

A switch (`/model <id>`) is stored immediately and takes effect from
the **next turn**. The currently running streaming subprocess is not
interrupted.

## Codex Runtime

`/model` with no args shows the stored override (or `(runtime default)`);
no model list is returned because the Codex runtime does not expose one.

A switch takes effect from the **next message** via an internal thread
fork — the conversation state is preserved and the new model is applied
transparently. From the user's perspective this is invisible.

## `/model reset`

Clears any stored override and restores the daemon's effective default
(set by `ALADUO_DEFAULT_RUNTIME` and the channel kind descriptor, or the
compiled-in baseline if neither is set). Takes effect on the next turn.

## Unknown / Unlisted Model Id

Any id without spaces is accepted and stored. The runtime decides whether
it is valid when the next turn runs. If the id is invalid:

- The turn will return an explanatory error message naming the invalid id.
- Billing stays on the previously effective model for that turn.
- Run `/model reset` (or `/model <correct-id>`) to recover.

## Finding Valid Model Ids

Use `/model` after starting a Claude session to see the ids the session
has observed. For a programmatic list, call the `system.config` RPC
method — the response includes the effective runtime and model settings
visible to the daemon.

## Cross-Runtime Cheat Sheet

| Behavior | Claude | Codex |
| --- | --- | --- |
| Model list with `/model` | yes (after first turn) | no |
| Switch takes effect | next turn | next message (thread fork) |
| `/model reset` timing | next turn | next message |
| Invalid id detection | next turn reply | next turn reply |
| Session disruption on switch | none | none |
