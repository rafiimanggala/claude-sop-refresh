#!/usr/bin/env bash
# watch.sh — UserPromptSubmit hook.
# If your instructions (CLAUDE.md + rules/*.md) changed since this session last
# saw them, inject the latest CLAUDE.md with a SUPERSEDES banner, then record
# the new version. Lazy by design: a refresh applies on the session's NEXT
# prompt after a change, never mid-task.
# Fail-safe: any error → emit {} so the prompt always proceeds.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh" 2>/dev/null || { printf '{}\n'; exit 0; }

LOG_FILE="${SCRIPT_DIR}/logs/sop.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
# Auto-rotate: keep the last 500 lines.
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1000 ]; then
  tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
fi
log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$LOG_FILE" 2>/dev/null || true; }
emit_empty() { printf '{}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || emit_empty

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[[ -z "$sid" ]] && emit_empty
sop_valid_sid "$sid" || emit_empty

cur="$(sop_version)"
seen="$(sop_read_seen "$sid")"

# Unseeded session (started before this hook existed): seed silently, no inject.
if [[ -z "$seen" ]]; then
  sop_write_seen "$sid" "$cur"
  log "seed-lazy" "session=${sid} version=${cur}"
  emit_empty
fi

# No change → nothing to do.
if [[ "$cur" == "$seen" ]]; then
  emit_empty
fi

# NOTE: no busy-status guard here. UserPromptSubmit ALWAYS fires at a turn
# boundary — the user is submitting a NEW prompt, so any prior task is already
# done. The session flips to "busy" the instant the prompt is submitted, so
# reading status here would (wrongly) report busy on EVERY turn and defer the
# refresh forever. The "wait until work is done" rule is satisfied structurally:
# the new instructions are consumed at the start of the next user turn.

# Changed → build the refresh payload from the latest CLAUDE.md.
sop_body="$(cat "$SOP_FILE" 2>/dev/null || true)"
[[ -z "$sop_body" ]] && { sop_write_seen "$sid" "$cur"; emit_empty; }

rules_list="$(find "$SOP_RULES_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort \
  | sed "s|${SOP_ROOT}/||" | tr '\n' ',' | sed 's/,$//')"

banner="[⚠️ INSTRUCTIONS REFRESHED — a change was detected since this session started]
REQUIRED: on the FIRST line of your reply, tell the user briefly: \"🔄 Instructions refreshed to the latest version (${seen:0:8} → ${cur:0:8})\". Then answer as usual.
The instructions below SUPERSEDE the version loaded at the start of this session.
If anything conflicts with the older copy in your context, FOLLOW THIS ONE.
On-demand rule files: ${rules_list} — re-read the relevant file when needed.

=== CLAUDE.md (LATEST) ===
${sop_body}"

# Record the new version BEFORE emitting (so a crash mid-emit won't re-fire forever).
sop_write_seen "$sid" "$cur"
log "refresh" "session=${sid} old=${seen} new=${cur} chars=${#banner}"

# systemMessage = the line VISIBLE to the user (refresh confirmation).
# additionalContext = the full instructions the model reads (not shown to user).
visible="🔄 INSTRUCTIONS REFRESH — CLAUDE.md/rules changed, latest version loaded (${seen:0:8} → ${cur:0:8})"
jq -ac -n --arg ctx "$banner" --arg msg "$visible" '{
  systemMessage: $msg,
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
