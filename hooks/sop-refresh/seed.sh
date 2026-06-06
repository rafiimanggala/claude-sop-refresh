#!/usr/bin/env bash
# seed.sh — SessionStart hook.
# Record the instruction version this session was BORN with, so watch.sh only
# fires on a LATER change (no false refresh on the very first prompt).
# Fail-safe: any error → exit 0, never block session start.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || exit 0

LOG_FILE="${SCRIPT_DIR}/logs/sop.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$LOG_FILE" 2>/dev/null || true; }

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[[ -z "$sid" ]] && exit 0
sop_valid_sid "$sid" || exit 0

ver="$(sop_version)"
sop_write_seen "$sid" "$ver"
log "seed" "session=${sid} version=${ver}"
exit 0
