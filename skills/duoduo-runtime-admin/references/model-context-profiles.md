# Model Profiles — guide the user, don't lecture them

Use this reference when the user wants third-party models to work properly on their
duoduo host: adding a model from a provider (DeepSeek, Bailian/Qwen, Kimi, GLM, an
aggregator gateway), routing different models to different endpoints, remapping
subagent tiers (`opus`/`sonnet`/`haiku`/`fable`), or understanding a `/model`
acknowledgement about rebuilding. Profiles are a Claude-runtime feature; codex
sessions have no profile namespace.

**Your job is to drive the workflow**: ask the few questions only the user can
answer, do the lookups and commands yourself, stop for confirmation before writes
and before anything that costs a rebuild. Explain in plain language — the mechanism
tables at the bottom are for *you*, not for pasting at the user.

**The custody rule: you may RECEIVE a secret, you must never RE-EMIT one.**
The human handing you an API key — pasted in Feishu, dropped in a file, exported
in the env — is a deliberate transfer of an asset to their agent. Accept it and
take custody immediately (Playbook 2b): into the profile store via the CLI, 0600,
masked in your confirmation. From that moment the raw value must never appear in
anything you produce — replies, summaries, logs, memory, boards. If the handover
happened in a chat, say so once, honestly: the chat history retains what they
pasted; suggest rotating the key if the channel was shared.

When the human can comfortably use a terminal, prefer guiding them through the
interactive form (the secret then never transits the chat at all) — but that is
an optimization, not a gate.

---

## Playbook 1 — "Add model X" (window only, same endpoint)

For a model served by the endpoint the host already uses.

1. **Get the real context window.** Ask if they have the provider's docs link; if
   not, look it up yourself (the provider's own model page or pricing page — an
   aggregator's listing is NOT evidence, see "How the numbers go wrong"). If
   sources disagree or the endpoint is a gateway, offer the probe (Playbook 5).
2. **Write it** (their scope of choice; global covers jobs and subconscious too):
   ```bash
   duoduo session config --global profile set <exact-model-id> <tokens>
   ```
   The id must be exactly what the endpoint accepts — aggregators rename models,
   and lookup is case-sensitive; a renamed id silently runs unprofiled.
3. **Confirm with `profile get`** and tell the user in one sentence what changed:
   *"duoduo now knows this model's real window, so it compacts before hitting the
   limit instead of dying at it."*
4. **Record the evidence** in the Markdown body of `kernel/config/runtime.md`
   (source URL + date). The body survives CLI writes; do this for them.

## Playbook 2 — "Route model X to its own endpoint" (base_url + credentials)

For running models from *different providers* on one host — e.g. deepseek models on
DeepSeek's API while qwen models stay on Bailian.

1. Window first (Playbook 1, step 1).
2. Ask which endpoint and which env var / key they use for it today. Explain
   where the credential will live: *"in the profile config file, plainly, like
   `settings.json` does — duoduo chmods the file 0600 and masks the value
   everywhere it displays it."*
3. **Get the token into custody — pick the path that fits how it arrives**:

   **(a) The human is at a terminal** — guide them; the secret never transits
   the chat:
   ```bash
   duoduo session config --global profile set deepseek-v4-pro 1000000 \
     --base-url https://api.deepseek.com/anthropic --auth-token-stdin
   # they paste the key at the hidden prompt
   ```

   **(b) The human hands YOU the key** (pasted in the channel, or it already
   lives in the host env / a key file) — do the setup yourself; the value must
   never appear in your command line, your reply, or anything else you emit:
   ```bash
   # key already in the host env:
   duoduo session config --global profile set deepseek-v4-pro 1000000 \
     --base-url https://api.deepseek.com/anthropic --auth-token-env DEEPSEEK_API_KEY
   # key you were just handed: write it to a 0600 temp file first (Write tool,
   # never echo), then:
   duoduo … profile set … --auth-token-file /path/to/keyfile && rm /path/to/keyfile
   ```
   Confirm with the masked value from `profile get`, and if the key arrived
   through a chat, add the one honest sentence: the chat history keeps what they
   pasted — rotate it if that channel is shared.

   `--oauth-token-*` variants exist for Claude-Code OAuth tokens; the field
   chosen decides which env variable the subprocess gets. There is deliberately
   no `--auth-token <value>` — argv is visible to every local process, including
   your own transcript.
4. Verify with `profile get`: base_url shows plainly, the token shows as
   `anthropic_auth_token: …1234`. If the user's kernel directory is a git repo,
   warn them once: *"this file now contains a key — add `config/runtime.md` to the
   kernel's .gitignore, or keep routed profiles at the session (instance) layer,
   which lives outside the kernel tree; both get the same 0600 treatment."*
5. Set expectations: *"switching this session to a model on another endpoint
   restarts its engine once — one-time cost, history survives. Same-endpoint,
   same-window switches stay free."* (Full pricing: Phrasebook below.)

## Playbook 3 — "Subagents should use the cheap model" (tier aliases)

The Agent tool only accepts `sonnet|opus|haiku|fable` — arbitrary ids error. Tier
aliases remap those names for everything in the process.

1. Ask which tier(s) they want remapped and to what. The target must be reachable
   through the endpoint that scope's sessions actually use — the CLI warns on a
   mismatch; take that warning seriously (a subagent runs inside its parent's
   process and cannot reach a different endpoint).
2. ```bash
   duoduo session config --global profile alias set opus deepseek-v4-pro
   ```
3. **Two warnings to relay in plain words**:
   - *"This changes what `opus` means everywhere in those sessions — `/model opus`
     and the model picker included, not just subagents."*
   - *"If you type `/model opus` yourself, duoduo can't apply the target model's
     window/routing protections — the alias is resolved deeper down. For top-level
     switches, use the concrete model id."*
4. Alias changes apply at the next engine start; a live session picks them up
   after its next rebuild (the ack will say so).

## Playbook 4 — "Profiles don't seem to work" (troubleshooting ladder)

Walk down; stop at the first hit.

1. `profile get` on the affected session — **Rejected entries** listed? A config
   file has a malformed entry; it fails the affected turns on purpose. Fix the
   named file or `profile unset` the bad entry (unset can always remove what the
   reader rejects). Tell the user the model itself is fine — no `/model reset`.
2. Model id mismatch — exact, case-sensitive; gateways rename. Compare `profile
   get` against what `/model` shows the session is actually running. `/model`
   with no args lists the same merged table from inside the session, so the user
   can check it themselves without a terminal — an id they expect to see and
   don't is a spelling problem, not a delivery one.
3. Bare tier alias — if the session's model is literally `opus`/`sonnet`/…,
   protections don't attach (Playbook 3, warning 2). Switch to the concrete id.
4. Legacy settings override — `~/.claude/settings.json` (or project scopes) with
   `env.CLAUDE_CODE_MAX_CONTEXT_TOKENS`: on older duoduo (≤ V1 delivery) that
   value silently beats every profile; `profile set` warns about it. On current
   duoduo, profiled models win, but *unprofiled* models still follow it. Grep the
   settings scopes; remove the key — profiles are its per-model replacement.
5. Nobody ever ran `/model` on this session — and it still answers wrong. The
   Claude CLI picks a model for itself in that case, and a `.claude/settings.json`
   in the session's workspace (or in `~`) is the usual place it gets one.
   **Current duoduo attaches the profile to that model too**, so this is fixed
   for free: run `/model` with no args and read the first line. It says
   `Session model: (runtime default → deepseek-v4-flash via project settings)`
   when a settings file chose a profiled model — the arrow tells you which model
   is really running and which file to open. On **older duoduo** the same setup
   silently ran the model with none of its routing (typical symptom: every turn
   returns "There's an issue with the selected model"), and the workaround was to
   type the id explicitly with `/model <id>` — if the user is on an older build
   and can't upgrade yet, that is still the fix. Note the CLI reads the settings
   `env: { "ANTHROPIC_MODEL": … }` block *before* the top-level `"model"` key, so
   check both.
6. The model is genuinely unprofiled — the `/model` ack says "No context profile
   is known". That's pass-through, not an error, but the engine then assumes
   a 1M window (see "No profile means 1M" below); offer Playbook 1. When a profile
   *did* apply, the same slot states the window instead
   (`Context window 1,000,000 tokens (global profile, routed endpoint).`), which
   is the fastest confirmation that a write took effect on a live session.

## Playbook 5 — "Make the endpoint confess its window" (the probe)

When docs conflict or a gateway is suspected of serving less than advertised
(both happen — see "How the numbers go wrong"):

Build a request deliberately past the suspected window with `max_tokens` capped
tiny (a rejection costs ~nothing), and read the limit out of the error — the
server's own number beats any documentation:

```bash
WORDS=300000   # ≈ tokens; set above your guess, adjust to bracket
python3 - "$WORDS" > /tmp/probe.json <<'PY'
import json, sys
print(json.dumps({"model": "<exact-model-id>", "max_tokens": 16,
  "messages": [{"role": "user", "content": "word " * int(sys.argv[1])}]}))
PY
curl -sS https://<endpoint>/v1/messages -H "x-api-key: $KEY_ENV_VAR" \
  -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  --data-binary @/tmp/probe.json | head -c 2000
# → "...maximum context length is N tokens..."  ← that N is your evidence
```

Key from env, never inline. If it succeeds instead of erroring, the guess was
low — raise and repeat.

---

## Phrasebook — say it like this

- **Why a profile at all**: "Without it duoduo has to assume a default window for
  this model. If the real one is smaller, requests die at the limit before cleanup
  ever runs; if larger, you waste context. The profile replaces the guess with the
  real number and everything downstream self-corrects."
- **The rebuild price**: "Changing a model's window, endpoint or credentials means
  the session's engine restarts once at the next message — its cache warms up from
  scratch and background helpers it spawned don't survive, but the conversation
  itself is untouched. Switching between same-setup models is free."
- **Comparing two models**: "Cheaper to open two sessions than to toggle one back
  and forth across endpoints — every crossing pays the restart."
- **Waiting for background work**: "If the session has helpers running, send the
  model switch after they finish — the switch itself never interrupts the current
  answer, so you control the timing."
- **Unprofiled**: "It still answers, but the engine assumes a 1M window for a
  model it doesn't know. If this model's real window is smaller, long
  conversations can hit the limit before cleanup runs. Let's add its real
  number."

## How the numbers go wrong (why evidence discipline exists)

- **A successor's number leaks backwards**: aggregators listed `glm-5.1` at 1M;
  the vendor's own docs say 200K — 1M belongs to the successor model. Copying the
  aggregator sets a cap five times reality, in the dangerous direction.
- **Two official numbers**: `qwen3.7-max` is documented as 256K in some places and
  1M in others, with no way to tell from outside which applies to an account and
  region. Probe; don't pick.
- **Gateways serve less than upstream advertises** (a public case: `kimi-k2.6`
  served at 32K while the API claimed 256K). The cap belongs to *the endpoint you
  actually call*, not to the model name.
- **The asymmetry**: too small merely wastes context; too large breaks turns.
  When in doubt, take the smaller number and note why.
- **No profile means 1M**: the bundled Claude Code (2.1.323+, duoduo 0.8.9+)
  assumes a 1M window for any model id it does not recognize (older builds
  assumed 200K). An unprofiled non-Anthropic model with a smaller real window
  is therefore oversized by default and can fail every turn at the limit
  before compaction runs. On a host that runs such models on the Claude
  runtime, profile each one.

### Reference table — starting points, not settled facts

Provider-documented values, verified on the date shown. **Re-verify before
trusting one**; your endpoint may not be the vendor's.

| Model id | Context window | Verified | Source |
| --- | --- | --- | --- |
| `deepseek-v4-pro` | 1000000 | 2026-07-30 | [DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing) |
| `deepseek-v4-flash` | 1000000 | 2026-07-30 | [DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing) |
| `kimi-k2.6` | 262144 | 2026-07-30 | [Kimi platform docs](https://platform.moonshot.cn/) |
| `glm-5.1` | 200000 | 2026-07-30 | [Z.AI model docs](https://docs.z.ai/guides/llm/glm-5.1) |

---

## Mechanism facts (for you; consult, don't recite)

**Layers & merge**: `kernel/config/runtime.md` (global — the only layer reaching
jobs/meta/subconscious) → `kernel/config/<kind>.md` → channel descriptor / job
frontmatter (instance, wins). Per model id / per alias tier, never whole-map.
`runtime` is a reserved kind name.

**Profile value forms** (`claude.model_profiles`): bare number = window only
(forever valid); object = `max_context_tokens` (required) + `base_url` + exactly
one of `anthropic_auth_token` / `claude_code_oauth_token` (values stored plainly;
file chmod'd 0600 when credentials present — runtime.md, kind files and
descriptors alike; every display path masks to last 4).

**Aliases** (`claude.model_aliases`): keys limited to
`fable|opus|sonnet|haiku`; delivered as `ANTHROPIC_DEFAULT_*_MODEL` to the
session's engine; process-global (all alias consumers move together); a bare tier
as the *top-level* session model bypasses profile lookup by design.

**Validation** (write-time, and read-time for hand edits): ids exact,
case-sensitive, no whitespace; `claude-*` and `[1m]`-suffixed keys rejected
(native models derive their own window; profile the base id — **the `[1m]` form
automatically uses the base id's profile**: same endpoint, same credentials, the
1M path only overrides the window, and toggling `model ↔ model[1m]` costs no
engine restart); positive whole-number tokens, raw window (no pre-subtracting
reserves).

**Fail-closed**: a malformed entry fails the affected turns naming layer+reason —
never a silent fallback to another layer. `profile get` lists rejected entries.
Bad aliases never fail turns (they only degrade tier mapping) but are listed too.

**Rebuild triggers** (claude): any change to window / base_url / auth / aliases →
one engine restart at the next message; same-tuple model swaps and switches to
native `claude-*` / `[1m]` are live. Codex: changes apply via thread fork
(history preserved) or automatically after a daemon restart.

**Host env fallback**: `CLAUDE_CODE_MAX_CONTEXT_TOKENS` remains a single-value
blanket for *unprofiled* models only; it cannot express a multi-model host and is
not a configuration surface. A settings-scope `env` entry of that key beats the
fallback for unprofiled models — remove it once profiles are in use.
