#!/usr/bin/env bash
# Reset one Feishu channel's persisted session state.
#
# Use when a chat has accumulated stale state (wrong runtime, abandoned
# experiments, a descriptor from a previous owner) and you want the next
# /setup to behave as if the channel had never been bound.
#
# Since duoduo 0.5.0 the daemon exposes `session.archive` — a single RPC
# that archives every durable artifact of a session (session dir, ingress
# snapshots, outbox records, channel descriptor) to its corresponding
# `<name>-archive/` sibling. This script finds every session_key that
# belongs to the given Feishu channel and feeds it to that CLI:
#
#     duoduo session archive <session_key>
#
# The Feishu plugin can run on a host DIFFERENT from the daemon host. The
# plugin's own state lives outside the daemon's filesystem, so it still
# needs a side-step:
#
#   daemon host   → one `duoduo session archive` call per session_key that
#                   references the channel_id. The CLI refuses when a
#                   session has a live actor; cancel it first via
#                   `duoduo channel feishu logs` + `/cancel`, or simply
#                   stop the feishu plugin so its actors drop.
#   plugin host   → prune `watched-sessions.json` entries containing the
#                   chat OpenID, then restart the plugin so it forgets the
#                   binding.
#
# "Archive", not delete. Every artifact moves under var/<kind>-archive/
# with a timestamp. To truly remove, `rm -rf` the archive dir by hand.
# To recover, `mv` it back.
#
# Exit codes: 0 success, 1 usage error, 2 target not found / nothing to do.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --channel-id <feishu-channel-id> [--role auto|daemon|plugin|both]
                                           [--aladuo-home PATH]
                                           [--plugin-cache PATH]
                                           [--keep-descriptor]
                                           [--duoduo-bin PATH]
                                           [--dry-run]

  --channel-id       Required. e.g. feishu-oc_5713a942f1e8e60d34b0ca644e3478b1
  --role             auto (default): do whatever this host supports.
                     daemon: only archive sessions + descriptor via the daemon.
                     plugin: only touch ~/.cache/feishu-channel.
                     both: force daemon + plugin steps (single-host install).
  --aladuo-home      Override \$HOME/.aladuo (daemon host root).
  --plugin-cache     Override \$HOME/.cache/feishu-channel (plugin host root).
  --keep-descriptor  Legacy flag, kept for compatibility. session.archive
                     currently archives the descriptor along with the
                     session; a future flag on the RPC could restore
                     opt-in descriptor retention. For now, passing this
                     flag produces a warning and proceeds without
                     descriptor-specific behavior.
  --duoduo-bin       Path to the duoduo CLI (default: whichever \`duoduo\`
                     is first on PATH). Useful when you have multiple
                     installs (e.g. \`~/.duoduo-manager/bin/duoduo\`).
  --dry-run          Print the plan without touching the daemon or filesystem.

Daemon host actions:
  1. Scan \$ALADUO_HOME/var/sessions/*/state.json for entries whose
     source_channel_id matches the channel_id.
  2. For each match, run \`duoduo session archive <session_key>\` — the
     daemon archives the session dir, ingress snapshots, outbox records,
     and the channel descriptor in one atomic RPC.

Plugin host actions:
  1. Remove entries matching the channel_id from watched-sessions.json.
  2. Print a reminder to restart the plugin:
       duoduo channel feishu stop && duoduo channel feishu start
EOF
}

CHANNEL_ID=""
ROLE="auto"
ALADUO_HOME="${HOME}/.aladuo"
PLUGIN_CACHE="${HOME}/.cache/feishu-channel"
KEEP_DESCRIPTOR=0
DRY_RUN=0
DUODUO_BIN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --channel-id) CHANNEL_ID="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --aladuo-home) ALADUO_HOME="${2:-}"; shift 2 ;;
    --plugin-cache) PLUGIN_CACHE="${2:-}"; shift 2 ;;
    --keep-descriptor) KEEP_DESCRIPTOR=1; shift ;;
    --duoduo-bin) DUODUO_BIN="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$CHANNEL_ID" ]; then
  echo "error: --channel-id is required" >&2
  usage >&2
  exit 1
fi
case "$ROLE" in
  auto|daemon|plugin|both) ;;
  *) echo "error: --role must be auto|daemon|plugin|both" >&2; exit 1 ;;
esac

# Resolve duoduo CLI. Callers running under the duoduo-manager app have the
# binary at ~/.duoduo-manager/bin/duoduo, which is not always on PATH.
if [ -z "$DUODUO_BIN" ]; then
  if command -v duoduo >/dev/null 2>&1; then
    DUODUO_BIN="$(command -v duoduo)"
  elif [ -x "${HOME}/.duoduo-manager/bin/duoduo" ]; then
    DUODUO_BIN="${HOME}/.duoduo-manager/bin/duoduo"
  fi
fi

if [ "$KEEP_DESCRIPTOR" -eq 1 ]; then
  echo "[reset-feishu-session] warning: --keep-descriptor is a no-op with session.archive." >&2
fi

log() { echo "[reset-feishu-session] $*"; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
}

has_daemon_state() { [ -d "$ALADUO_HOME/var/sessions" ]; }
has_plugin_state() { [ -d "$PLUGIN_CACHE" ]; }

do_daemon=0
do_plugin=0
case "$ROLE" in
  daemon) do_daemon=1 ;;
  plugin) do_plugin=1 ;;
  both) do_daemon=1; do_plugin=1 ;;
  auto)
    has_daemon_state && do_daemon=1 || true
    has_plugin_state && do_plugin=1 || true
    if [ "$do_daemon" -eq 0 ] && [ "$do_plugin" -eq 0 ]; then
      echo "error: neither $ALADUO_HOME/var/sessions nor $PLUGIN_CACHE exists" >&2
      echo "       run with --role explicitly on the correct host" >&2
      exit 2
    fi
    ;;
esac

# -------- daemon host --------
if [ "$do_daemon" -eq 1 ]; then
  if ! has_daemon_state; then
    echo "error: --role implies daemon work but $ALADUO_HOME/var/sessions not found" >&2
    exit 2
  fi
  if [ -z "$DUODUO_BIN" ]; then
    echo "error: duoduo CLI not found (checked PATH and ~/.duoduo-manager/bin/duoduo)." >&2
    echo "       pass --duoduo-bin /absolute/path/to/duoduo" >&2
    exit 2
  fi

  SESSIONS_DIR="$ALADUO_HOME/var/sessions"

  log "scanning $SESSIONS_DIR for state.json referencing channel_id=$CHANNEL_ID"

  # Collect matching session_keys. grep returns 1 on no-match — guard with
  # `|| true` so set -e does not abort on an empty result.
  HITS_FILE="$(mktemp)"
  grep -l "\"source_channel_id\"[[:space:]]*:[[:space:]]*\"$CHANNEL_ID\"" \
    "$SESSIONS_DIR"/*/state.json 2>/dev/null > "$HITS_FILE" || true

  if [ ! -s "$HITS_FILE" ]; then
    log "no session state.json under $SESSIONS_DIR references $CHANNEL_ID"
    log "nothing to archive on the daemon host (descriptor, if any, will"
    log "be left in place — it is archived by session.archive together"
    log "with an owning session)."
    rm -f "$HITS_FILE"
  else
    # Extract session_keys before invoking the RPC so one stuck session
    # doesn't prevent archiving the others.
    KEYS_FILE="$(mktemp)"
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      # state.json always carries session_key in Phase 3+; it's the primary
      # reverse-lookup field the daemon itself uses.
      KEY="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('session_key') or '')" "$hit" 2>/dev/null || echo "")"
      if [ -n "$KEY" ]; then
        echo "$KEY" >> "$KEYS_FILE"
      fi
    done < "$HITS_FILE"
    rm -f "$HITS_FILE"

    if [ ! -s "$KEYS_FILE" ]; then
      log "matching state.json files lack session_key — cannot archive"
      log "(install is older than Phase 1 of session-state-refactor?)"
      rm -f "$KEYS_FILE"
      exit 2
    fi

    while IFS= read -r key; do
      [ -z "$key" ] && continue
      log "archiving session $key via daemon RPC"
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] $DUODUO_BIN session archive $key"
      else
        # `duoduo session archive` exit codes: 0 archived or not_found,
        # 2 refused (active actor or bad args), 1 daemon error.
        if ! "$DUODUO_BIN" session archive "$key"; then
          log "FAILED to archive $key — session may still be active."
          log "Cancel it first (e.g. /cancel via the daemon) then retry."
        fi
      fi
    done < "$KEYS_FILE"
    rm -f "$KEYS_FILE"
  fi
fi

# -------- plugin host --------
if [ "$do_plugin" -eq 1 ]; then
  if ! has_plugin_state; then
    echo "error: --role implies plugin work but $PLUGIN_CACHE not found" >&2
    exit 2
  fi
  WATCHED="$PLUGIN_CACHE/watched-sessions.json"
  if [ ! -f "$WATCHED" ]; then
    log "no $WATCHED — plugin has not cached any sessions yet, nothing to prune"
  else
    # Extract the chat OpenID portion of the channel_id (strip "feishu-" prefix).
    CHAT_ID="${CHANNEL_ID#feishu-}"
    log "pruning session_keys containing $CHAT_ID from watched-sessions.json"
    if [ "$DRY_RUN" -eq 1 ]; then
      python3 - "$WATCHED" "$CHAT_ID" <<'PY'
import json, sys
path, chat = sys.argv[1], sys.argv[2]
d = json.load(open(path))
sessions = d.get("sessions", [])
kept = [s for s in sessions if chat not in s]
print(f"[dry-run] would rewrite {path}: {len(sessions)} → {len(kept)}")
PY
    else
      python3 - "$WATCHED" "$CHAT_ID" <<'PY'
import json, sys, os, tempfile
path, chat = sys.argv[1], sys.argv[2]
d = json.load(open(path))
before = len(d.get("sessions", []))
d["sessions"] = [s for s in d.get("sessions", []) if chat not in s]
after = len(d["sessions"])
# Atomic rewrite: write to sibling tmp then rename.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".watched-")
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
os.replace(tmp, path)
print(f"[reset-feishu-session] watched-sessions.json: {before} → {after}")
PY
    fi
  fi
  log "IMPORTANT: restart the plugin so it reloads the watched list:"
  log "  duoduo channel feishu stop && duoduo channel feishu start"
fi

log "done"
