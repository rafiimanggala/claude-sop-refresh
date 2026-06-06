#!/usr/bin/env bash
# lib.sh — shared helpers for live-refreshing your Claude Code instructions
# (CLAUDE.md + rules/*.md) across every running session.
# Sourced by seed.sh (SessionStart) and watch.sh (UserPromptSubmit).

SOP_ROOT="${HOME}/.claude"
SOP_FILE="${SOP_ROOT}/CLAUDE.md"
SOP_RULES_DIR="${SOP_ROOT}/rules"
SOP_NONCE="${SOP_ROOT}/.sop-nonce"
SOP_ENV_DIR="${SOP_ROOT}/session-env"
SOP_SESS_DIR="${SOP_ROOT}/sessions"

# Read a session's live status (idle|busy|shell|...) from Claude Code's own
# per-PID registry. Empty if unknown.
sop_session_status() {
  local sid="$1" f st
  [[ -z "$sid" ]] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  for f in "$SOP_SESS_DIR"/*.json; do
    [[ -e "$f" ]] || continue
    st="$(jq -r --arg s "$sid" 'select(.sessionId==$s) | .status // empty' "$f" 2>/dev/null)"
    [[ -n "$st" ]] && { printf '%s' "$st"; return 0; }
  done
  return 0
}

# Reject a session id that is anything other than [A-Za-z0-9_-].
# session_id comes from JSON on stdin; refusing odd characters stops path
# traversal (e.g. "../../tmp/x") when sid is interpolated into a filesystem path.
sop_valid_sid() {
  case "$1" in
    ''|*[!0-9A-Za-z_-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# True if the path is part of your instructions (CLAUDE.md or any rules/*.md).
sop_is_sop_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  [[ "$p" == "$SOP_FILE" ]] && return 0
  [[ "$p" == "$SOP_RULES_DIR/"* ]] && return 0
  return 1
}

# Hash stdin robustly — a hook's PATH may lack /sbin, so resolve a digest tool
# explicitly. A constant fallback would silently disable change detection.
_sop_hash() {
  if command -v md5 >/dev/null 2>&1; then md5 -q
  elif [ -x /sbin/md5 ]; then /sbin/md5 -q
  elif command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif [ -x /usr/bin/shasum ]; then /usr/bin/shasum -a 256 | cut -d' ' -f1
  else cat >/dev/null 2>&1; printf 'NOHASH'; fi
}

# Compute current version = digest of CLAUDE.md + all rules/*.md + nonce.
# Memory / daily logs are intentionally EXCLUDED (they change constantly).
sop_version() {
  {
    cat "$SOP_FILE" 2>/dev/null
    find "$SOP_RULES_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort \
      | while IFS= read -r f; do cat "$f" 2>/dev/null; done
    cat "$SOP_NONCE" 2>/dev/null
  } | _sop_hash 2>/dev/null || printf 'NOVER'
}

# Path to a session's last-seen-version marker.
# Defense-in-depth: refuse to build a path from an invalid sid.
sop_seen_file() {
  local sid="$1"
  sop_valid_sid "$sid" || return 1
  printf '%s/%s/sop-seen' "$SOP_ENV_DIR" "$sid"
}

# Read the version a given session last saw (empty if none).
sop_read_seen() {
  local sid="$1" f
  f="$(sop_seen_file "$sid")" || return 0
  cat "$f" 2>/dev/null || true
}

# Record the version a session has now seen.
sop_write_seen() {
  local sid="$1" ver="$2" f
  f="$(sop_seen_file "$sid")" || return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  printf '%s' "$ver" > "$f" 2>/dev/null || true
}
