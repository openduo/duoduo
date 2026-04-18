#!/usr/bin/env bash
# v05-upgrade-preflight.sh
#
# Accelerator for the v0.5 upgrade playbook. Collects, in one pass, the
# facts an agent needs to choose the right upgrade branch:
#
#   * installed duoduo version
#   * latest published version on npm
#   * daemon running / stopped
#   * channels installed and running
#   * key FEISHU_* env settings
#   * whether any Feishu channel already has a descriptor on disk, and
#     whether each descriptor is v0.5-shaped (has bound_by) or pre-v0.5
#
# Output is markdown. Each section header is stable so the agent can
# grep for it. Missing tools / permission errors are reported inline
# rather than making the whole script abort — the agent may still be
# able to complete the upgrade manually even if one probe fails.
#
# This script is an ACCELERATOR, not the only path. If the script
# itself fails to run (missing bash features, sandbox denies a cmd,
# something renames the paths in a future release), the agent can
# reproduce every probe by hand — the markdown body explains exactly
# what each block would show. See references/upgrade-playbook.md.

set +e   # keep going when individual probes fail
set -u

# Be deliberately lenient about availability of tools — the agent
# consumes whatever sections produce output.
DUODUO_HOME="${ALADUO_HOME:-$HOME/.aladuo}"
DUODUO_ENV_FILE="${DUODUO_ENV_FILE:-$HOME/.config/duoduo/.env}"

echo "# duoduo v0.5 upgrade preflight"
echo
echo "Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo

# ── Version ────────────────────────────────────────────────────────
echo "## Version"
echo
# `duoduo --version` sometimes writes to stderr depending on CLI
# version / banner suppression state; capture both streams.
INSTALLED_VERSION="$(duoduo --version 2>&1 | head -n1 || echo '(duoduo CLI not found)')"
echo "- installed: \`${INSTALLED_VERSION}\`"
if command -v npm >/dev/null 2>&1; then
  LATEST_VERSION="$(npm view @openduo/duoduo version 2>/dev/null || echo '(npm view failed)')"
  echo "- latest on npm: \`${LATEST_VERSION}\`"
else
  echo "- latest on npm: (npm not in PATH; agent should fetch with an alternative tool if needed)"
fi
echo

# ── Daemon ─────────────────────────────────────────────────────────
echo "## Daemon"
echo
if command -v duoduo >/dev/null 2>&1; then
  DAEMON_STATUS="$(duoduo daemon status 2>&1 | head -n 20 || echo '(status call failed)')"
  echo '```'
  echo "$DAEMON_STATUS"
  echo '```'
else
  echo "- duoduo CLI not on PATH; cannot query daemon status"
fi
echo

# ── Channels ───────────────────────────────────────────────────────
echo "## Installed channels"
echo
if command -v duoduo >/dev/null 2>&1; then
  CHANNEL_LIST="$(duoduo channel list 2>&1 || echo '(channel list failed)')"
  echo '```'
  echo "$CHANNEL_LIST"
  echo '```'
else
  echo "- duoduo CLI not on PATH; cannot enumerate channels"
fi
echo

# ── Feishu specifics ───────────────────────────────────────────────
echo "## Feishu channel state (v0.5 relevant)"
echo
HAS_FEISHU=no
if command -v duoduo >/dev/null 2>&1; then
  if duoduo channel list 2>/dev/null | grep -qE "^feishu[[:space:]]"; then
    HAS_FEISHU=yes
  fi
fi
echo "- feishu channel installed: ${HAS_FEISHU}"

if [ "$HAS_FEISHU" = "yes" ]; then
  echo
  echo "### env keys (in \`${DUODUO_ENV_FILE}\`)"
  echo
  if [ -r "$DUODUO_ENV_FILE" ]; then
    for KEY in FEISHU_BOT_OWNER FEISHU_ALLOW_FROM FEISHU_DM_POLICY FEISHU_GROUP_POLICY FEISHU_GROUP_CMD_USERS; do
      VAL="$(grep -E "^${KEY}=" "$DUODUO_ENV_FILE" 2>/dev/null | head -n1 || true)"
      if [ -n "$VAL" ]; then
        echo "- \`${VAL}\`"
      else
        echo "- \`${KEY}\`: (not set)"
      fi
    done
  else
    echo "- env file not readable at \`${DUODUO_ENV_FILE}\`"
  fi
  echo
  echo "### descriptors on disk"
  echo
  DESC_DIR="${DUODUO_HOME}/var/channels"
  if [ -d "$DESC_DIR" ]; then
    FOUND_DESC=no
    for d in "${DESC_DIR}"/feishu-*/; do
      [ -d "$d" ] || continue
      FOUND_DESC=yes
      CHANNEL_ID="$(basename "$d")"
      DESC_PATH="${d}descriptor.md"
      if [ -r "$DESC_PATH" ]; then
        # Detect presence of bound_by field in the descriptor's
        # frontmatter; agent uses this to tell v0.5 vs pre-v0.5
        # bindings apart (pre-v0.5 falls back to
        # FEISHU_GROUP_CMD_USERS allowlist for /setup).
        if grep -qE "^bound_by:[[:space:]]*ou_" "$DESC_PATH" 2>/dev/null; then
          SHAPE="v0.5 (has bound_by)"
        else
          SHAPE="pre-v0.5 (no bound_by — legacy binding)"
        fi
        echo "- \`${CHANNEL_ID}\`: ${SHAPE}"
      else
        echo "- \`${CHANNEL_ID}\`: (descriptor not readable)"
      fi
    done
    if [ "$FOUND_DESC" = "no" ]; then
      echo "- no feishu-* descriptors found (no Feishu channel has ever been bound)"
    fi
  else
    echo "- descriptors dir \`${DESC_DIR}\` does not exist yet"
  fi
fi
echo

# ── Recommended branch ─────────────────────────────────────────────
echo "## Recommended branch"
echo
if [ "$HAS_FEISHU" = "no" ]; then
  echo "- **Branch B** (no-feishu): run the standard upgrade sequence. No"
  echo "  special v0.5 configuration needed. See"
  echo "  \`references/upgrade-playbook.md\` → 'Branch B'."
else
  MISSING_KEYS=""
  if [ -r "$DUODUO_ENV_FILE" ]; then
    for KEY in FEISHU_BOT_OWNER FEISHU_DM_POLICY; do
      if ! grep -qE "^${KEY}=" "$DUODUO_ENV_FILE" 2>/dev/null; then
        MISSING_KEYS="${MISSING_KEYS}${KEY} "
      fi
    done
  fi
  if [ -n "$MISSING_KEYS" ]; then
    echo "- **Branch D** (feishu + missing security env): MUST discuss"
    echo "  with the user BEFORE the upgrade — after upgrade, zero-config"
    echo "  behavior means strangers who can reach the bot auto-spawn into"
    echo "  the main session. Missing keys: \`${MISSING_KEYS}\`. See"
    echo "  \`references/upgrade-playbook.md\` → 'Branch D'."
  else
    echo "- **Branch C** (feishu + env configured): safe to proceed with"
    echo "  the standard upgrade sequence, then verify /setup behavior"
    echo "  matches the v0.5 matrix. See"
    echo "  \`references/upgrade-playbook.md\` → 'Branch C'."
  fi
fi
echo

exit 0
