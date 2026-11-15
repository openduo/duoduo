# Pi Runtime

Use this reference before enabling or explaining Pi support.

## Prerequisites

Pi ships **inside** duoduo — the pi coding-agent SDK is pinned as a
dependency. There is nothing to install and no availability probe: the
daemon always reports pi as available. That is availability, not
readiness — a provider credential is still needed, and getting one in
place is its own section below. What a pi session DOES need:

- **A model pointer.** Pi has no runtime default model inside duoduo: a
  pi session without one fails with an actionable message instead of
  silently running on something else. Canonical form is
  `provider/modelId` (e.g. `deepseek/deepseek-flash`). Three sources: a
  stored `/model`, job frontmatter `model:`, partition frontmatter
  `model:`. A stored `/model` wins over job frontmatter — on a job too,
  where both can exist.
- **The host user's pi agent dir** (`~/.pi/agent`): `models.json`,
  `auth.json`, settings, extensions, and skills are reused as-is —
  including providers registered by the user's own extensions. Duoduo
  never writes into it; per-session model-store writes are diverted
  into duoduo's own runtime state.

A fresh host has neither — an untouched `~/.pi/agent` means pi is
available and configured with nothing, so every pi session refuses. See
"Configuring a provider" below; it does not require installing pi.

Useful check: if the bundled pi CLI answers in a terminal project dir
with the model the user expects, duoduo can use the same providers and
credentials — it reads the same files.

## Host-Mode Availability

There is no `ALADUO_PI_ENABLED` env var and no auto-detection step —
pi is embedded, so it appears as an available runtime on every host.
"Available" is not "configured": the failure surface is per-session,
at message time, with the fix named in the reply (most commonly a
missing model pointer).

Do **not** set `PI_CODING_AGENT_DIR` in production — it is a test seam;
production daemons must land on the real `~/.pi/agent`.

Duoduo has no config key that hands pi a provider credential: channel
descriptors and model profiles do not reach it, so putting a pi key
there does nothing. The two carriers that work are pi's own
`auth.json` / `models.json` and the daemon's environment — see
"Configuring a provider" below.

## Configuring a provider (the pi CLI ships inside duoduo)

"The user has not installed pi" is almost always a false premise, and it is
the reason this section exists: duoduo pins the pi package, and that package
ships a full CLI. It is there on every host that has duoduo:

```bash
PI="$(npm root -g)/@openduo/duoduo/node_modules/.bin/pi"
"$PI" --help
```

Prefer this copy over a separately installed `pi` even when one is on PATH:
it is by construction the version duoduo runs, and extension compatibility is
judged against that version (see Caveats). A globally installed `pi` can drift
away from it after either side is upgraded.

**Configuring pi IS configuring duoduo's pi.** Both read the same two files —
duoduo passes `<agent-dir>/auth.json` and `<agent-dir>/models.json` explicitly,
where the agent dir is `PI_CODING_AGENT_DIR` or `~/.pi/agent`. Duoduo never
writes them. So the answer to "how do I configure a provider" is always "the
way pi documents it", and the only duoduo-specific parts are whose home
directory the daemon runs as, and the env-var caveat below.

### Credential resolution order

Pi resolves a provider's credential in this order — later sources are only
consulted when the earlier ones are absent:

1. `--api-key` on the CLI (not a duoduo path; the daemon never passes it)
2. `auth.json` entry — API key or OAuth token
3. environment variable
4. the provider's own `apiKey` in `models.json`

### Path A — `/login` (a human at a terminal)

Start the bundled CLI interactively and run `/login`. This is the only path
that gets **subscription OAuth** (Claude Pro/Max, ChatGPT Plus/Pro, GitHub
Copilot, xAI, OpenRouter, Radius); tokens land in `auth.json` and refresh
themselves. `/login <provider-id>` targets one provider directly, including a
custom one declared in `models.json`. `/logout` clears it.

Over SSH the browser cannot reach the loopback callback. Pi's own docs give
the fallback for the OpenRouter PKCE flow — paste the final redirect URL or
authorization code into the login prompt. Try that before concluding a
subscription login is impossible on a remote host; whether every provider's
flow offers it is not something this reference has verified.

### Path B — write `auth.json` (no TUI at all)

The file is a flat map of provider id → credential — no wrapper key, unlike
`models.json` below. An API-key entry:

```json
{
  "deepseek": { "type": "api_key", "key": "sk-..." },
  "openai":   { "type": "api_key", "key": "!op read op://vault/openai/credential" }
}
```

`key` takes the same three forms everywhere pi reads a credential: a literal, a
`$ENV_VAR` / `${ENV_VAR}` indirection, or `!command` — the last runs a program
and uses its stdout, which is how a host keeps the secret in a manager instead
of on disk. It is also the form immune to a scrubbed daemon environment.

Keep the file `0600` (pi writes it that way itself). This is the whole
mechanism for API-key providers — no registration step, and the worker picks
the file up on its **next build** (see the table above).

OAuth entries live in the same file and are written by `/login`; they carry
`{"type":"oauth","access":…,"refresh":…,"expires":…}` and refresh themselves.
Hand-editing those is not a supported path — re-run `/login` instead.

### Path C — environment variable

Every built-in provider has an env var name (`ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`,
`GROQ_API_KEY`, …). Do not transcribe a list from memory — `"$PI" --help`
prints the current one, which is the same map pi resolves against.

An env var alone is sufficient: no `auth.json` entry is needed for a built-in
provider. **But it must be in the DAEMON's environment**, not the operator's
shell — that mismatch is the single most common "it works when I run pi, not
in duoduo" report.

`~/.config/duoduo/.env` is the carrier: the daemon loads that file at boot and
every key in it goes into the daemon's environment, not just the `ALADUO_*`
ones. It never overrides a variable the process already has, so a value
inherited from the launching shell wins over the file. On deployments that
start the daemon with a scrubbed environment (`env -i`), the file still loads —
what a scrub costs you is the shell-exported variables, so the file is the more
reliable of the two. One exception to know: when the host's Claude auth source
is the local Claude Code login, the daemon deliberately clears the
`ANTHROPIC_*` model vars after loading, so that specific family is not a
dependable way to feed pi's `anthropic` provider — use `auth.json` for it.

A `.env` edit reaches pi only after a daemon restart; the file is read at boot.

### Path D — `models.json` for an endpoint pi does not know

Self-hosted, gateway, or any OpenAI/Anthropic/Google-compatible endpoint. A
provider entry declares `baseUrl`, `api`, `apiKey`, and its own `models` list —
pi does **not** probe `/v1/models`, so what you declare is what it knows:

```json
{
  "providers": {
    "my-gateway": {
      "baseUrl": "https://gateway.internal/v1",
      "api": "openai-completions",
      "apiKey": "$MY_GATEWAY_KEY",
      "models": [
        {
          "id": "some-model",
          "name": "Some Model",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": 131072,
          "maxTokens": 8192,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

The `providers` wrapper is required — a bare provider map is rejected with
`Invalid models.json schema: providers: must have required properties
providers`, and pi then continues with the file ignored rather than failing
loudly. A `Warning: errors loading models.json` line at startup is the only
tell, so check it after every hand edit.

`api` is one of `openai-completions`, `openai-responses`, `anthropic-messages`,
`google-generative-ai`, plus the vendor-specific ones (`azure-openai-responses`,
`openai-codex-responses`, `google-vertex`, `bedrock-converse-stream`,
`mistral-conversations`, `pi-messages`). Both `api` and `baseUrl` must resolve
for a custom model — from the model entry or the provider above it — or the
entry is rejected. `id` is the only strictly required model field; omitted ones
default, and two of those defaults are worth overriding on purpose:
`contextWindow` falls back to 128000 and `maxTokens` to 16384, which will be
silently wrong for a model that differs.

Keyless local servers still need a placeholder `apiKey`: pi treats a model as
unavailable until *some* credential resolves.

Use this path whenever the vendor is not one of pi's ~40 built-ins. A common
case in China: there is **no `bailian` / DashScope built-in** — Aliyun appears
only as the `qwen-token-plan*` providers, so a Bailian endpoint has to be
declared here as a custom OpenAI-compatible provider.

The context window you declare here is pi's; duoduo's own model-context
profiles are a **Claude-runtime** concept and do not apply to pi.

### Verifying, without starting a session

```bash
"$PI" auth check --provider deepseek --json   # {"status":"ready","provider":"deepseek","authType":"api_key"}
"$PI" --list-models deepseek                  # rows: provider, model, context, max-out, thinking, images
```

Three things to know before reading the answers:

- `auth check` reports whether a credential was **found**, not whether it
  works — a syntactically fine but invalid key reports `ready`. The first real
  turn is still where a bad key surfaces. The failure forms differ and say
  different things: `not_ready` + `credentials_not_configured` means nothing
  resolved, while `invalid` + `invalid_state` means the provider itself did not
  load — with a hand-edited `models.json`, read that as a schema error, not a
  credential problem.
- `--list-models` is **already credential-filtered**: a provider with no
  resolvable credential contributes no rows. So an id missing from the list is
  usually an auth question, not a catalog question.
- Both commands answer for **your** shell. Duoduo's in-session `/model` asks the
  same question inside the daemon's environment, so a model that appears here
  and not there is the env-var caveat above — the key is in your shell and not
  in the daemon's. That divergence is the diagnostic, not a bug.

`pi auth print-api-key` / `print-bearer-token` exist and are for feeding an
external client. **Never run them to show a user their key** — printing a
credential into a chat transcript or a log is the one thing this whole surface
must not do. Do not pass keys as command-line arguments either (`ps` leak);
write them into the file or the env file.

### After configuring, force the worker rebuild

A running pi session does not re-read the agent dir between messages. Once the
credential is in place, `duoduo daemon restart -r "configured <provider> for pi"`
— see the table above for which edits need this and which do not.

## Runtime Selection

Duoduo picks a runtime by specificity:

1. Actor-level declaration, such as a channel descriptor, job
   frontmatter, or partition frontmatter (`runtime: pi`).
2. Channel-kind default in `kernel/config/<kind>.md`.
3. Global default: `ALADUO_DEFAULT_RUNTIME` (`claude`, `codex`,
   `grok`, or `pi`).
4. Conservative fallback: `claude`.

**Pi has no silent Claude fallback.** An explicit `runtime: pi` (or a
pi global default) whose session has no resolvable model is a hard
failure at drain time, with the fix named in the reply. Codex and
grok take the same no-fallback posture when unavailable.

## `/model` and `/effort` on pi

Both are **store-only** on pi: the value persists immediately, and the
per-session worker process is rebuilt with it on the next message —
both are construction-time facts of the worker, so there is no live
hot-switch and no next-turn surprise beyond that one rebuild.

- `/model provider/modelId` — the id must carry the slash. A bare id
  is rejected up front rather than guessing the provider. `/model
  reset` clears the override, but a pi session still needs SOME model
  source afterwards; with none, the next message fails actionably.
- `/effort <level>` — the levels map 1:1 onto pi's native
  thinking levels.

`/model` with no argument on a pi session reports the stored id, or
`(none set)` when there is none — never `(runtime default)`, which
would be a lie on a runtime that has none. It also lists the model ids
this installation can actually run, grouped by provider:

```
Usable now (`/model` also accepts any other id pi can resolve):
- **bailian**: `bailian/qwen3.7-max`, `bailian/glm-5.1`, …
- **glm-coding**: `glm-coding/glm-5.3`
```

Two rules decide what appears, and the second one is the useful one:

- **Declared here** — from `models.json` or an extension that calls
  `registerProvider`. Pi ships a large built-in provider catalog; none
  of it is listed unless this installation asked for it.
- **Credentialed for THIS daemon** — a provider you configured but whose
  key the daemon cannot see is simply absent. That is deliberate: if you
  configured something and cannot see it, the config is where to look.
  Note the daemon is not your shell — a `$VAR` key that works when you
  run `pi` in a terminal must also reach the daemon (see the pi
  Caveats below), and this list is the surface that shows the difference.

Absence never blocks anything: `/model <id>` still accepts any id pi can
resolve. The list is answered by a short-lived worker that loads your
extensions, so it costs a second or two and no tokens; if it cannot be
produced the section is simply omitted.

## Applying a change to `~/.pi/agent`

**A pi session runs one long-lived worker process, and it does not
re-read your agent dir between messages.** The worker is rebuilt only
when one of its construction facts changes: model, effort, the settings
seed, project-trust default, or the `pi.extensions` / `pi.skills`
selection. Extension file contents, `models.json` and `auth.json` are
not among them — the daemon cannot tell they changed.

| what you edited | when it takes effect |
| --- | --- |
| `/model`, `/effort` | next message |
| `settings.json` behaviour + resource keys | next message |
| `settings.json` `defaultModel` / `defaultProvider` / `enabledModels` / proxy / TUI keys | **never** — duoduo drops them; a restart does not help. Use `/model`. |
| `settings.json` `cacheWarming` | **never** — duoduo keeps pi's default (`idle` since pi 1.5.1: between runs pi may re-send the last request to keep the provider cache warm) and drops the key. |
| `pi.extensions` / `pi.skills` (below) | next message |
| **an extension**, `models.json`, `auth.json`, a `/login`, project trust | **next worker build** |

There is no duoduo equivalent of pi's `/reload`. To force the rebuild:

```bash
duoduo daemon restart -r "installed <extension>"    # all pi sessions
```

A session that has completed a turn resumes its history from its session
file on the next message. (`--wake <session>` is unrelated: it is for
sessions whose turn the restart cut off, same as any runtime.) Leaving
the session idle past `ALADUO_SESSION_IDLE_MS` also rebuilds it, as does
`/clear` — but `/clear` throws the conversation away, so it is the wrong
tool here.

**The symptom that misleads people:** `/model` with no argument answers
from a throwaway worker, so it lists a newly installed provider
immediately while the running session still cannot use it. Catalog lists
the provider **and** the live session calls that same model "not
resolvable" ⇒ rebuild the worker.

**When an extension fails to load, the error is not in the reply.** The
worker logs it to stderr at debug level only — set
`ALADUO_LOG_LEVEL=debug` to see `extension FAILED to load: …`. If the
failed extension was the one registering the selected model, the user
sees "model not resolvable", which blames the model id; otherwise the
session runs on and only the log knows. On an installation where
providers come from extensions, check the loader before the id.

### Choosing which extensions load

`pi.extensions` and `pi.skills` take `all` (the default) or `none`. The
config lives in `kernel/config/<kind>.md` or a channel instance
descriptor; **for a job it is the job file's own frontmatter**, and job
creation APIs do not expose it.

```yaml
pi:
  extensions: none
```

`none` also drops every provider those extensions register — on a host
whose models come from an extension, `none` makes them unresolvable.

A list is accepted but is **not** a filter over discovered extensions:
it turns discovery off and loads exactly the source paths given, so the
entries must be paths, not names.

Instance **replaces** kind rather than unioning. An invalid value is
logged and ignored, which means an instance falls back to the kind's
selection, not to `all`.

### Binding a channel to pi

A channel session bound to pi from a setup card is **not ready to talk
yet** — there is no model until someone sets one, so the first message
comes back refused. The Feishu bind confirmation says so inline; on
surfaces that show only a toast, the refusal on the first message is
where the operator finds out. Setting the model is a one-liner and the
session works from the next message on:

```
/model <provider>/<modelId>
```

The refusal is per MESSAGE, not per session: once the model is stored,
the very next message runs. If a host instead keeps replaying the same
refusal after a successful `/model`, it is running a build from before
that fix — restarting the daemon clears it, and the stored model then
takes effect.

## Subconscious partitions

A partition opts in with frontmatter `runtime: pi` **plus**
`model: provider/modelId`. A pi partition without a model fails
actionably (the error names the frontmatter fix) — it never falls
through to Claude. Partition runs are stateless by construction: an
in-memory pi session per tick, no session file written. Nothing
survives a tick except files the partition itself writes.

Partitions always load `extensions: all` / `skills: all` — partition
frontmatter does not parse `pi.*`, so the selection above has no effect
there.

## ManageJob

- `runtime: pi` is a valid create parameter (pi is always available).
  The job needs frontmatter `model: provider/modelId`.
- `prompt_mode` applies to **claude, grok, and pi** (`append` default,
  or `override`). Combining `prompt_mode` with `runtime: codex` is
  rejected; combining it with pi is accepted.
- Delegation FROM a pi session is `ManageJob` — there is no `Agent`
  tool on pi (see Caveats).

## Context and compaction

Pi runs its own threshold compaction and duoduo inherits the settings
from `~/.pi/agent/settings.json`. The file is optional; these are pi's
defaults:

```json
{
  "compaction": {
    "enabled": true,
    "reserveTokens": 16384,
    "keepRecentTokens": 20000
  }
}
```

It rides the settings seed, so an edit lands on the session's **next
message** — no daemon restart (the settings-seed row of the table
above). It is global to the agent dir: the same file governs the pi CLI
a human runs by hand, and duoduo has no per-session override for it.

### `keepRecentTokens` under-counts CJK by roughly 3x

Pi sizes the retained slice with a `chars / 4` heuristic. That is
correct for English and wrong for Chinese, Japanese and Korean, where a
token is closer to 1.5 characters. Measured on a production Chinese
session:

| | |
| --- | --- |
| real ratio, assistant text | 1.28-1.85 chars/token (median ~1.55) |
| heuristic assumes | 4 chars/token |
| `keepRecentTokens` configured | 20,000 |
| tokens actually retained | ~73,000 |

Two effects compound: the character heuristic (~2.6x) and whole-turn
rounding, because the cut lands on a turn boundary and a large turn is
kept entire. End to end the slice ran **~3.7x the configured budget**.

So on a CJK session every compaction leaves a much higher floor than
the number suggests, and the working room before the next one is much
smaller. Size against the multiplier:

```
keepRecentTokens = desired_retained_tokens / 3.7
```

Measure the multiplier on the session rather than trusting 3.7:
compare an assistant message's character count against the
`output_tokens` its usage-ledger record carries. English-dominant
sessions need no adjustment.

### When the window fills anyway: one-character replies

Pi caps each request's output at what the context window has left over.
Once the conversation has filled the window that residue hits its floor
of **1 token**, and the request goes out at that cap instead of
failing. What the operator sees:

- the reply is a single character, and it is a grammatical opening —
  the first token of the answer the model meant to give
- the turn finishes normally; no error surfaces anywhere in duoduo
- cost is at maximum: the entire context is written to the prompt cache
  every turn at a 0% hit rate

`var/usage/<session_key>.jsonl` (or the `usage.get` RPC) carries the
signature: `output_tokens: 1` next to a full
`cache_creation_input_tokens`. Tool calls in that state are truncated
mid-arguments and come back "was not executed: the response hit the
output token limit".

Recovery, in this order:

1. `duoduo session model <session> <model-with-a-larger-window>`.
   Compaction was observed to stop producing summaries while the window
   was wedged; the model switch is what let it run again.
2. `duoduo session compact <session>`, then set the model back.
3. Lower `keepRecentTokens` so the next floor leaves working room.

Raising the declared `contextWindow` in a provider extension is not a
fix unless the backend really serves the larger window — verify with an
authenticated `GET <base_url>/v1/models` before editing the extension.

## Caveats

These are protocol-level trade-offs, not "Pi is a second-class engine"
issues:

- **Extension compatibility is judged against duoduo's pinned pi
  version**, not whatever the standalone pi package currently ships. A
  user extension written for a newer pi may fail to load here; the
  worker logs the load error and continues.
- **Extension-triggered runs outside a duoduo turn are "orphan runs".**
  During a duoduo turn, a run deferred from an `agent_settled` handler
  is not one: since pi 1.0 it finishes before that turn closes, so its
  text is the turn's reply and its tokens count toward the turn. A run
  with no owning duoduo turn is an orphan: its text does
  not ride the turn's reply and **its tokens do not reach the usage
  ledger at all** — ledger attribution is not implemented; the frame is
  logged at debug level and dropped. Model calls an extension makes
  through its own client (a subagent package, typically) are invisible
  to duoduo for a different reason — they never reach the session at
  all. Either way the turn under-reports its cost.
- **A hard kill is not clean for detached shells.** The worker's
  shutdown ladder kills the background process groups it can see, but
  a `nohup`-style orphan that fully re-parented can survive — same
  caveat as running pi in a terminal.
- **`"$ENV_VAR"` API keys need the variable present in the daemon's
  environment.** Deployments that start the daemon with a scrubbed
  environment (`env -i`) must whitelist those variables, or those
  providers fail with "No API key". The `!command` credential form is
  immune (it runs a program instead of reading env).
- **User `packages` sources may touch the network.** A settings
  `packages` list pointing at git/npm sources resolves them on load —
  on firewalled hosts, route or mirror them like any other dependency,
  or the load stalls.
- **Compaction is two-layer.** Pi's own threshold compaction stays on
  (it inherits the user's pi settings — see Context and compaction
  above, including the CJK sizing correction). Duoduo's idle
  auto-compact ALSO applies to pi with the same two knobs as Claude
  (`auto_compact_idle_minutes` + `auto_compact_min_context_tokens`),
  OFF until both are set. Codex remains the only excluded runtime.
- **Project trust is reused, never answered for duoduo's user.** A
  directory is trusted because the user ran pi there once (or their
  settings' `defaultProjectTrust` says `always`). Duoduo never
  auto-confirms a trust prompt; an untrusted project simply loads no
  project extensions.
- **`permission_profile` does not apply to pi in v1.** Pi runs as a
  bypass peer, exactly like Codex and Grok. Claude remains the only
  runtime with the permission ladder.
- **No `Agent` / `TaskStop` on pi.** Delegation is
  `ManageJob` (spawn a job, get notified). Subconscious partitions
  that want pi-native subagents can install a project `.pi/extensions`
  package themselves — that is pi's own mechanism, not duoduo's.
- **There is no tool allowlist on pi, deliberately.** Pi's own `tools`
  option filters user-extension tools along with duoduo's, so duoduo
  passes none and an extension's tools are active by default. The only
  filter is `disallowedTools`, a denylist by tool name, read at worker
  build time — changing it mid-session is deferred to the next rebuild.
  Do not reason from Claude's `claude.tools` allowlist here; it is the
  opposite shape.
