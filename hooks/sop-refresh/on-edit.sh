#!/usr/bin/env bash
# on-edit.sh: PostToolUse hook (matcher: Write|Edit|MultiEdit).
# When a session edits CLAUDE.md or any rules/*.md, remind the editing agent to
# ASK the user before broadcasting the refresh to all live sessions.
# This is the "auto-detect, but confirm first" half of the feature.
# Fail-safe: any error → emit {} so nothing is blocked.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || { printf '{}\n'; exit 0; }

LOG_FILE="${SCRIPT_DIR}/logs/sop.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$LOG_FILE" 2>/dev/null || true; }
emit_empty() { printf '{}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || emit_empty

input="$(cat 2>/dev/null || true)"
[[ -z "$input" ]] && emit_empty

fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"

# Only react to edits of the instructions themselves.
sop_is_sop_path "$fp" || emit_empty

# Count other live sessions (excluding self) that would receive the broadcast.
others=0
if [[ -d "$SOP_SESS_DIR" ]]; then
  for f in "$SOP_SESS_DIR"/*.json; do
    [[ -e "$f" ]] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"; [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -0 "$pid" 2>/dev/null || continue
    osid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
    [[ "$osid" == "$sid" ]] && continue
    others=$((others+1))
  done
fi

# Mark a pending broadcast (editor + target file + time) for visibility.
printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${sid:-?}" "$fp" >> "${SOP_ROOT}/.sop-pending" 2>/dev/null || true
log "edit-detected" "session=${sid} file=${fp} other_live=${others}"

rel="${fp#"$SOP_ROOT"/}"
ctx="[⚠️ INSTRUCTIONS CHANGED: ${rel}]
You just edited your instructions. This edit ALREADY triggers an automatic refresh in every session (the hash changed). There are ${others} other live session(s) running.
REQUIRED before continuing: ASK the user whether to broadcast the refresh to all sessions now.
- Yes → run \`sop-refresh\` (forces a re-broadcast and prints each session's status).
- A session that is BUSY will automatically wait until its task finishes, then receive the new instructions on its next turn.
- An idle/active session receives the new instructions on its next prompt.
Do not broadcast without the user's confirmation."

jq -ac -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
