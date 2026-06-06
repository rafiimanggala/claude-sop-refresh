#!/usr/bin/env bash
# install.sh: install claude-sop-refresh.
#
#   ./install.sh             copy files + print the settings.json snippet to add
#   ./install.sh --register  also merge the hooks into ~/.claude/settings.json
#                             (a timestamped backup is made first)
#   BIN_DIR=/custom/bin ./install.sh   override where the CLI is installed
#
# Idempotent: re-running overwrites the installed scripts and won't duplicate
# hook entries when --register is used.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DST="${CLAUDE_DIR}/hooks/sop-refresh"
BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"
SETTINGS="${CLAUDE_DIR}/settings.json"
REGISTER=0
[[ "${1:-}" == "--register" ]] && REGISTER=1

say() { printf '%s\n' "$*"; }

# --- dependency checks -------------------------------------------------------
command -v jq >/dev/null 2>&1 || { say "✗ jq is required (brew install jq / apt install jq)"; exit 1; }
if ! command -v md5 >/dev/null 2>&1 && ! command -v md5sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  say "✗ need one of: md5, md5sum, or shasum (for change detection)"; exit 1
fi

# --- copy files --------------------------------------------------------------
mkdir -p "$HOOK_DST" "$BIN_DIR"
cp "$REPO_DIR/hooks/sop-refresh/"*.sh "$HOOK_DST/"
cp "$REPO_DIR/bin/sop-refresh" "$BIN_DIR/sop-refresh"
chmod +x "$HOOK_DST"/*.sh "$BIN_DIR/sop-refresh"
say "✓ hooks → $HOOK_DST"
say "✓ CLI   → $BIN_DIR/sop-refresh"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "⚠ $BIN_DIR is not on your PATH, add it so 'sop-refresh' is callable." ;;
esac

# --- the hook config to add --------------------------------------------------
read -r -d '' SNIPPET <<'JSON' || true
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash $HOME/.claude/hooks/sop-refresh/seed.sh", "timeout": 5 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash $HOME/.claude/hooks/sop-refresh/watch.sh", "timeout": 5 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|MultiEdit", "hooks": [ { "type": "command", "command": "bash $HOME/.claude/hooks/sop-refresh/on-edit.sh", "timeout": 5 } ] }
    ]
  }
}
JSON

if [[ "$REGISTER" -eq 0 ]]; then
  say ""
  say "Next step, add these hooks to $SETTINGS (merge into any existing \"hooks\"):"
  say ""
  say "$SNIPPET"
  say ""
  say "Or re-run with --register to merge them automatically."
  exit 0
fi

# --- --register: merge into settings.json (with backup) ----------------------
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
BACKUP="${SETTINGS}.bak-sop-$(date -u +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$BACKUP"
say "✓ backup → $BACKUP"

# Append our entries to each event array, skipping any that already point at our
# scripts (so re-running --register is idempotent).
tmp="$(mktemp)"
jq '
  def want(ev): $snippet.hooks[ev][0];
  def has_ours(ev; needle):
    (.hooks[ev] // []) | any(.hooks[]?.command | test(needle));
  .hooks = (.hooks // {})
  | .hooks.SessionStart   = ((.hooks.SessionStart   // []) + (if has_ours("SessionStart"; "sop-refresh/seed.sh")     then [] else [want("SessionStart")]   end))
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + (if has_ours("UserPromptSubmit"; "sop-refresh/watch.sh") then [] else [want("UserPromptSubmit")] end))
  | .hooks.PostToolUse    = ((.hooks.PostToolUse    // []) + (if has_ours("PostToolUse"; "sop-refresh/on-edit.sh")    then [] else [want("PostToolUse")]    end))
' --argjson snippet "$SNIPPET" "$SETTINGS" > "$tmp"

if jq -e . "$tmp" >/dev/null 2>&1; then
  mv "$tmp" "$SETTINGS"
  say "✓ hooks registered in $SETTINGS"
  say "  Restart running sessions once (or start a new one) so the hooks load."
else
  rm -f "$tmp"
  say "✗ merge produced invalid JSON, left $SETTINGS untouched. Add the snippet manually."
  exit 1
fi
