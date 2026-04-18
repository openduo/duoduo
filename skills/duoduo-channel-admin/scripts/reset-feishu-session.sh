#!/usr/bin/env bash
# Reset one Feishu channel's persisted session state.
#
# Use when a chat has accumulated stale state (wrong runtime, abandoned
# experiments, a descriptor from a previous owner) and you want the next
# /setup to behave as if the channel had never been bound.
#
# The Feishu plugin can run on a host DIFFERENT from the daemon host. State
# is split accordingly:
#
#   daemon host  (has ~/.aladuo/var/sessions/):
#     - session dirs under ~/.aladuo/var/sessions/<hash>/ keyed by session_key
#     - channel descriptor at ~/.aladuo/var/channels/<channel_id>/
#
#   feishu plugin host  (has ~/.cache/feishu-channel/):
#     - watched-sessions.json listing every session_key the plugin is
#       attached to via websocket
#     - plugin process must be restarted for the file change to take effect
#
# When both halves run on the same machine (the common case), default
# --role=auto handles both. For a truly split deployment, run the script
# with --role=daemon on the daemon host and --role=plugin on the plugin host.
#
# Exit codes: 0 success, 1 usage error, 2 target not found / nothing to do.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --channel-id <feishu-channel-id> [--role auto|daemon|plugin|both]
                                           [--aladuo-home PATH]
                                           [--plugin-cache PATH]
                                           [--keep-descriptor]
                                           [--dry-run]

  --channel-id       Required. e.g. feishu-oc_5713a942f1e8e60d34b0ca644e3478b1
  --role             auto (default): do whatever this host supports.
                     daemon: only touch ~/.aladuo (session dirs + descriptor).
                     plugin: only touch ~/.cache/feishu-channel.
                     both: force daemon + plugin steps (single-host install).
  --aladuo-home      Override \$HOME/.aladuo (daemon host root).
  --plugin-cache     Override \$HOME/.cache/feishu-channel (plugin host root).
  --keep-descriptor  Leave the channel descriptor in place. The next /setup
                     will still be a "re-bind" (warning copy) instead of a
                     fresh "first-time" welcome.
  --dry-run          Print what would happen; change nothing on disk.

Daemon host actions:
  1. Find every session dir whose state.json references channel_id.
  2. Move each session dir to \$ALADUO_HOME/var/sessions/.trash/<name>.<ts>.
  3. Move the channel descriptor to var/channels/.trash/<id>.<ts>.
     Skipped when --keep-descriptor.

Plugin host actions:
  1. Remove entries matching the channel_id from watched-sessions.json.
  2. Print a reminder to restart the plugin: duoduo channel feishu stop && duoduo channel feishu start.

Nothing is deleted outright — everything goes to a .trash sibling with a
timestamp suffix so recovery is a simple \`mv\` back.
EOF
}

CHANNEL_ID=""
ROLE="auto"
ALADUO_HOME="${HOME}/.aladuo"
PLUGIN_CACHE="${HOME}/.cache/feishu-channel"
KEEP_DESCRIPTOR=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --channel-id) CHANNEL_ID="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --aladuo-home) ALADUO_HOME="${2:-}"; shift 2 ;;
    --plugin-cache) PLUGIN_CACHE="${2:-}"; shift 2 ;;
    --keep-descriptor) KEEP_DESCRIPTOR=1; shift ;;
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

TS="$(date +%s)"

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
}

log() { echo "[reset-feishu-session] $*"; }

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
  SESSIONS_DIR="$ALADUO_HOME/var/sessions"
  TRASH_SESSIONS="$SESSIONS_DIR/.trash"
  run "mkdir -p '$TRASH_SESSIONS'"

  log "searching session dirs for channel_id=$CHANNEL_ID"
  # grep -l prints the state.json path; we want the enclosing hash dir.
  # Use a temp file + while-read so this works on macOS's bash 3.2 (no mapfile).
  HITS_FILE="$(mktemp)"
  grep -l "\"source_channel_id\"[[:space:]]*:[[:space:]]*\"$CHANNEL_ID\"" \
    "$SESSIONS_DIR"/*/state.json 2>/dev/null > "$HITS_FILE" || true

  INGRESS_DIR="$ALADUO_HOME/var/ingress"
  TRASH_INGRESS="$INGRESS_DIR/.trash"
  OUTBOX_DIR="$ALADUO_HOME/var/outbox"
  TRASH_OUTBOX="$OUTBOX_DIR/.trash"

  if [ ! -s "$HITS_FILE" ]; then
    log "no session dirs reference $CHANNEL_ID — skipping session cleanup"
  else
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      dir="$(dirname "$hit")"
      base="$(basename "$dir")"

      # Extract session_key from state.json BEFORE moving the dir, so we
      # can match the outbox replay log (which is keyed by session_key,
      # not by session dir hash).
      SESSION_KEY="$(python3 -c "import json; print(json.load(open('$hit')).get('session_key',''))" 2>/dev/null || echo "")"

      log "moving session dir $base → .trash/$base.$TS"
      run "mv '$dir' '$TRASH_SESSIONS/$base.$TS'"

      # CRITICAL: also move the matching ingress snapshot dir. Agents
      # can read `var/ingress/<hash>/` via ManageSession(show) and quote
      # historical messages verbatim — so leaving it behind lets a fresh
      # session "remember" everything the reset was supposed to clear.
      # The enclosing hash directory name is shared: session hash == ingress hash.
      INGRESS_HIT="$INGRESS_DIR/$base"
      if [ -d "$INGRESS_HIT" ]; then
        run "mkdir -p '$TRASH_INGRESS'"
        log "moving ingress dir $base → ingress/.trash/$base.$TS"
        run "mv '$INGRESS_HIT' '$TRASH_INGRESS/$base.$TS'"
      fi

      # CRITICAL: outbox replay log is named after session_key. When
      # session_key is reused (same chat + same cwd → same hash), a fresh
      # session inherits the old replay log — containing full text of
      # every previous reply. Leaving it behind lets the agent quote all
      # prior bot replies verbatim.
      if [ -n "$SESSION_KEY" ]; then
        REPLAY_FILE="$OUTBOX_DIR/replay/${SESSION_KEY}.jsonl"
        if [ -f "$REPLAY_FILE" ]; then
          run "mkdir -p '$TRASH_OUTBOX/replay'"
          log "moving outbox replay log for $SESSION_KEY → outbox/.trash/replay/"
          run "mv '$REPLAY_FILE' '$TRASH_OUTBOX/replay/$(basename "$REPLAY_FILE").$TS'"
        fi

        # Also clean outbox/<channel_kind>/obx_*.json entries whose
        # session_key matches. These are per-record files; many are
        # already status=sent, but they still contain full payload text
        # and can be read by the agent. Scan every channel_kind subdir
        # (feishu, lark, etc.) because the record's channel_kind is the
        # PROTOCOL family, not the channel_id prefix.
        for KIND_DIR in "$OUTBOX_DIR"/*/; do
          KIND_NAME="$(basename "$KIND_DIR")"
          case "$KIND_NAME" in
            replay|.trash) continue ;;
          esac
          MATCHES_FILE="$(mktemp)"
          grep -l "\"session_key\"[[:space:]]*:[[:space:]]*\"$SESSION_KEY\"" \
            "$KIND_DIR"*.json 2>/dev/null > "$MATCHES_FILE" || true
          if [ -s "$MATCHES_FILE" ]; then
            COUNT=$(wc -l < "$MATCHES_FILE" | tr -d ' ')
            run "mkdir -p '$TRASH_OUTBOX/$KIND_NAME'"
            log "moving $COUNT outbox/$KIND_NAME/*.json records for $SESSION_KEY → outbox/.trash/$KIND_NAME/"
            while IFS= read -r rec; do
              [ -z "$rec" ] && continue
              run "mv '$rec' '$TRASH_OUTBOX/$KIND_NAME/$(basename "$rec").$TS'"
            done < "$MATCHES_FILE"
          fi
          rm -f "$MATCHES_FILE"
        done
      fi
    done < "$HITS_FILE"
  fi
  rm -f "$HITS_FILE"

  # Belt-and-suspenders outbox cleanup: the per-session loop above only
  # fires when a LIVE session dir still exists. If a prior reset already
  # moved the session away (or the user mvs it by hand), those outbox
  # records stay. Do a second pass keyed on the chat's chat_id (derived
  # from channel_id by stripping the "feishu-" prefix). Feishu lark
  # session_keys always embed chat_id as `lark:<chat_id>:...`. Match
  # records whose session_key contains the chat_id substring; replay
  # files whose filename starts with `lark:<chat_id>:`.
  CHAT_ID="${CHANNEL_ID#feishu-}"
  if [ "$CHAT_ID" != "$CHANNEL_ID" ]; then
    # Replay logs keyed by session_key in filename.
    REPLAY_MATCHES="$(mktemp)"
    ls "$OUTBOX_DIR/replay/" 2>/dev/null | grep -F "lark:$CHAT_ID:" > "$REPLAY_MATCHES" || true
    if [ -s "$REPLAY_MATCHES" ]; then
      COUNT=$(wc -l < "$REPLAY_MATCHES" | tr -d ' ')
      run "mkdir -p '$TRASH_OUTBOX/replay'"
      log "extra pass: moving $COUNT residual outbox replay log(s) matching $CHAT_ID"
      while IFS= read -r fname; do
        [ -z "$fname" ] && continue
        run "mv '$OUTBOX_DIR/replay/$fname' '$TRASH_OUTBOX/replay/$fname.$TS'"
      done < "$REPLAY_MATCHES"
    fi
    rm -f "$REPLAY_MATCHES"

    # Per-record files across all channel_kind subdirs.
    for KIND_DIR in "$OUTBOX_DIR"/*/; do
      KIND_NAME="$(basename "$KIND_DIR")"
      case "$KIND_NAME" in
        replay|.trash) continue ;;
      esac
      MATCHES_FILE="$(mktemp)"
      grep -l "\"session_key\"[[:space:]]*:[[:space:]]*\"lark:$CHAT_ID:" \
        "$KIND_DIR"*.json 2>/dev/null > "$MATCHES_FILE" || true
      if [ -s "$MATCHES_FILE" ]; then
        COUNT=$(wc -l < "$MATCHES_FILE" | tr -d ' ')
        run "mkdir -p '$TRASH_OUTBOX/$KIND_NAME'"
        log "extra pass: moving $COUNT residual outbox/$KIND_NAME/*.json record(s) for chat $CHAT_ID"
        while IFS= read -r rec; do
          [ -z "$rec" ] && continue
          run "mv '$rec' '$TRASH_OUTBOX/$KIND_NAME/$(basename "$rec").$TS'"
        done < "$MATCHES_FILE"
      fi
      rm -f "$MATCHES_FILE"
    done

    # Also second-pass ingress — when a prior reset moved session dir,
    # new session hash may not exist yet, but old ingress trash dir may
    # still contain session-key artifacts if naming collides. Scan live
    # ingress dirs by content — grep each for channel_id reference.
    INGRESS_RESIDUAL="$(mktemp)"
    grep -l "\"channel_id\"[[:space:]]*:[[:space:]]*\"$CHANNEL_ID\"" \
      "$INGRESS_DIR"/*/*.json 2>/dev/null > "$INGRESS_RESIDUAL" || true
    if [ -s "$INGRESS_RESIDUAL" ]; then
      # Group by enclosing dir, move each dir at most once.
      sort -u -t'/' -k"$(echo "$INGRESS_DIR" | tr -cd '/' | wc -c | tr -d ' ')" "$INGRESS_RESIDUAL" > "${INGRESS_RESIDUAL}.dirs" || true
      SEEN="$(mktemp)"
      while IFS= read -r evt; do
        [ -z "$evt" ] && continue
        idir="$(dirname "$evt")"
        if grep -qxF "$idir" "$SEEN" 2>/dev/null; then continue; fi
        echo "$idir" >> "$SEEN"
        ibase="$(basename "$idir")"
        run "mkdir -p '$TRASH_INGRESS'"
        log "extra pass: moving residual ingress dir $ibase → ingress/.trash/$ibase.$TS"
        run "mv '$idir' '$TRASH_INGRESS/$ibase.$TS'"
      done < "$INGRESS_RESIDUAL"
      rm -f "$SEEN" "${INGRESS_RESIDUAL}.dirs"
    fi
    rm -f "$INGRESS_RESIDUAL"
  fi

  DESC_DIR="$ALADUO_HOME/var/channels/$CHANNEL_ID"
  TRASH_CHANNELS="$ALADUO_HOME/var/channels/.trash"
  if [ "$KEEP_DESCRIPTOR" -eq 1 ]; then
    log "--keep-descriptor: leaving $DESC_DIR in place"
  elif [ -d "$DESC_DIR" ]; then
    run "mkdir -p '$TRASH_CHANNELS'"
    log "moving descriptor $CHANNEL_ID → channels/.trash/$CHANNEL_ID.$TS"
    run "mv '$DESC_DIR' '$TRASH_CHANNELS/$CHANNEL_ID.$TS'"
  else
    log "no descriptor at $DESC_DIR — skipping"
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
