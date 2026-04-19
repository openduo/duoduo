# Upgrade playbook (host mode)

Load this reference when the user asks to upgrade duoduo — especially
when they mention v0.5, "升级 duoduo", "升级到 v0.5", or a specific
version bump.

## One-line summary

Standard upgrade is two commands:

```bash
npm install -g @openduo/duoduo@latest
duoduo daemon restart
```

The rest of this playbook only matters when (a) the user is crossing
the v0.5 boundary AND has a Feishu channel, or (b) something goes
wrong and we need to fall back to first-principles.

## Step 1 — Preflight (accelerator)

Run the preflight script to collect upgrade-relevant facts in one
pass:

```bash
bash scripts/v05-upgrade-preflight.sh
```

Output is markdown. Look for the "Recommended branch" section at the
bottom — it names one of **Branch B / C / D** described below.

### If the preflight script is unavailable or errors

Reproduce each probe manually (every section of the script is
documented here so the agent can skip the script entirely):

```bash
duoduo --version                       # installed version
npm view @openduo/duoduo version       # latest published
duoduo daemon status                   # daemon running?
duoduo channel list                    # any feishu / wechat / acp?
grep -E '^FEISHU_(BOT_OWNER|ALLOW_FROM|DM_POLICY|GROUP_POLICY|GROUP_CMD_USERS)=' \
  ~/.config/duoduo/.env                # security env snapshot
ls ~/.aladuo/var/channels/feishu-*/descriptor.md 2>/dev/null
for d in ~/.aladuo/var/channels/feishu-*/; do
  grep -E '^bound_by:' "${d}descriptor.md" || echo "  (no bound_by — pre-v0.5)"
done
```

Then decide the branch by hand:

- No feishu channel installed → **Branch B**.
- Feishu installed AND `FEISHU_BOT_OWNER` set AND
  `FEISHU_DM_POLICY=allowlist` → **Branch C**.
- Feishu installed AND any of those keys missing → **Branch D**.

## Step 2 — Pick the branch

### Branch A — fresh install (not really an upgrade)

Skip this playbook. Send the user to onboarding (`duoduo` CLI from
empty state). Nothing v0.5-specific to discuss until they have a
channel configured.

### Branch B — upgrade, no Feishu

```bash
npm install -g @openduo/duoduo@latest
duoduo daemon restart
```

Then verify:

```bash
duoduo --version                      # should show 0.5.x now
duoduo daemon status                  # healthy: yes; version: 0.5.x
```

Done. No further v0.5-specific action needed — the trust-boundary
changes only affect the Feishu channel.

### Branch C — upgrade with Feishu + security env already set

Safe to proceed. The agent should:

1. Run the upgrade:
   ```bash
   npm install -g @openduo/duoduo@latest
   duoduo daemon restart
   ```
2. Restart the Feishu plugin to pick up the new plugin bundle (the
   plugin is a separate process; daemon restart does not restart it):
   ```bash
   duoduo channel feishu stop
   duoduo channel feishu start
   ```
3. Verify:
   ```bash
   duoduo --version
   duoduo channel list                # feishu shows @openduo/channel-feishu@0.5.x, running
   ```
4. Brief the user on the two new /setup behaviors they'll observe:
   - Owner DM (their personal DM with the bot): first message
     auto-spawns the main session; no setup card.
   - Groups: already-configured groups now show a compact "current
     configuration" card (mention toggle only) on `/setup`.

Hand off to `duoduo-channel-admin` → `references/feishu.md` for the
full behavior matrix if the user wants to see every case.

### Branch D — upgrade with Feishu but missing security env

⚠️ **Discuss with the user BEFORE running the upgrade.** After
upgrade, zero-config mode means any first DM sender triggers
auto-spawn into the owner's main session. With `dmPolicy=open` (the
default), strangers who reach the bot become the bot's main session.

Walk the user through:

1. Confirm the bot owner's Feishu open_id. Ask them to /whoami in
   an existing chat with the bot, OR grep Feishu developer console.
2. Propose additions to `~/.config/duoduo/.env`:
   ```bash
   FEISHU_BOT_OWNER=ou_<theirOpenId>
   FEISHU_ALLOW_FROM=ou_<theirOpenId>,ou_<friend>,...   # if not already set
   FEISHU_DM_POLICY=allowlist                           # if not already set
   ```
3. Show the diff with the existing `.env` and ask for confirmation
   before writing (sensitive file).
4. Write the additions using
   `duoduo-runtime-admin`'s
   [scripts/update_host_env.py](../../duoduo-runtime-admin/scripts/update_host_env.py)
   if available, otherwise hand-edit.
5. Then proceed with Branch C's upgrade + restart sequence.

If the user refuses to set security env right now, document the
risk in chat and let them proceed into "bootstrap mode" with their
eyes open. Do not block the upgrade — but do warn explicitly.

### Pre-v0.5 descriptors (legacy groups / DMs)

The preflight marks each existing descriptor as "v0.5 (has bound_by)"
or "pre-v0.5 (no bound_by — legacy binding)". Legacy descriptors
continue to work without migration. Their `/setup`:

- Groups: fall back to `FEISHU_GROUP_CMD_USERS` allowlist for the
  compact rebind card's permission check.
- p2p (DMs): route through the secondary-DM card path (no ⌂) so
  the user can still reassign project.

No action required for legacy descriptors unless the user reports a
specific problem with one.

## SDK architecture change landing in v0.5

v0.5 upgrades the bundled `@anthropic-ai/claude-agent-sdk` to
0.2.114, which ships the Claude Code runtime as a per-platform
native binary via npm optional dependencies (e.g.
`@anthropic-ai/claude-agent-sdk-darwin-arm64`). Implications for
upgraders:

- `npm install -g @openduo/duoduo@0.5.x` will download the
  platform-specific binary (~200 MB) automatically. On slow
  networks this is the new long step; previous versions only
  fetched JS.
- Installs with `npm install --omit=optional` or
  `NPM_CONFIG_OPTIONAL=false` will succeed but the daemon will
  refuse to start, with an actionable error naming the missing
  `@anthropic-ai/claude-agent-sdk-<platform>-<arch>` package.
  Reinstall without the flag, or set `CLAUDE_CODE_EXECUTABLE`
  to a compatible binary you already have.
- Users who previously installed `@anthropic-ai/claude-code` as
  a separate global package can uninstall it — duoduo now carries
  its own copy via the SDK. Keeping the standalone install is
  harmless but not required.
- Third-party compatible endpoints (sglang, LiteLLM proxies,
  older Bedrock/Vertex) may reject `thinking.type=adaptive`
  requests with HTTP 4xx. The daemon now surfaces this as a
  `[duoduo:drain-error]` reply instead of silence. The common
  workaround is setting `DISABLE_ADAPTIVE=1 DISABLE_THINKING=1
  DISABLE_INTERLEAVED_THINKING=1 MAX_THINKING_TOKENS=0` in
  `~/.config/duoduo/.env` and restarting the daemon.

## Step 3 — Post-upgrade verification

Always verify:

```bash
duoduo --version                       # 0.5.x
duoduo daemon status                   # healthy: yes; version: 0.5.x
duoduo channel list                    # each channel shows 0.5.x versions
```

If a channel shows an older version than expected, restart that
channel explicitly:

```bash
duoduo channel <kind> stop
duoduo channel <kind> start
```

If the daemon reports an older version than expected, the upgrade
`npm install` likely raced with a restart; re-run:

```bash
duoduo daemon stop
duoduo daemon start
```

(There is no `duoduo daemon restart` override that forces a fresh
binary load beyond this — the `restart` subcommand IS stop+start.)

## Step 4 — If something goes wrong

Fall back to first-principles diagnosis:

- Daemon won't start: check `duoduo daemon logs` for the first
  stack trace.
- Channel won't start: `duoduo channel <kind> logs`.
- Feishu-specific symptoms after upgrade: route to
  `duoduo-channel-admin` → `references/diagnose-feishu.md`.
- Accepted v0.5 limits (first-time group race, env typo unlock) are
  documented in `duoduo-channel-admin` →
  `references/feishu.md#accepted-v05-limits`.

The script is an accelerator. If it fails to run at all — sandbox
blocks it, missing bash features, PATH resolution issues — the agent
can still run every probe manually as shown in Step 1's fallback
section, and then follow the branch logic from there. Do NOT treat
the script as the only path.
