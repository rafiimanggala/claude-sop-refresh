# claude-sop-refresh

**Edit your Claude Code instructions once, every running session picks them up on its next turn. No restart, no lost context.**

Claude Code loads your `CLAUDE.md` and `rules/*.md` **once, at session start**. If you keep several sessions open across terminals and edit those files mid-session, the running sessions keep following the **stale** instructions until you restart them, and restarting throws away the conversation.

`claude-sop-refresh` is a small set of hooks (+ a CLI) that watches `CLAUDE.md` and `rules/*.md`, and when they change, injects the latest version into **every live session** on its next prompt. Lazy by design: the refresh lands at a turn boundary, so it never interrupts a task in progress.

```
edit ~/.claude/CLAUDE.md
        │
        ▼
 hash changes ──> every live session, on its next prompt:
        │            "🔄 Instructions refreshed (a1b2c3d4 → e5f6a7b8)"
        │            + latest CLAUDE.md injected, marked SUPERSEDES
        ▼
 sop-refresh        (optional) force a re-broadcast + see who picks it up
```

## Why this isn't native (yet)

Claude Code can already hot-reload some things, but **not** your memory files:

| Mechanism | Reloads | Scope | Trigger |
|-----------|---------|-------|---------|
| `/reload-skills` | skills + commands | current session | manual |
| `/reload-plugins` | plugins / MCP | current session | manual |
| settings.json hot-reload | permissions, hooks, env | all sessions | automatic |
| **`CLAUDE.md` / `rules/`** | (none) | (none) | **nothing native** |
| **claude-sop-refresh** | **CLAUDE.md + rules** | **all sessions** | **automatic, on file change** |

If Anthropic ships native memory hot-reload, great, this becomes obsolete and you uninstall it. Until then, this fills the gap.

## How it works

Three hooks, all fail-safe (any error → they emit `{}` / exit 0 and never block a prompt):

- **`seed.sh`** (`SessionStart`), records the instruction version this session was born with, so a refresh only fires on a *later* change (no false refresh on the first prompt).
- **`watch.sh`** (`UserPromptSubmit`), hashes `CLAUDE.md` + `rules/*.md` each prompt; if the hash differs from what this session last saw, injects the latest `CLAUDE.md` with a SUPERSEDES banner and a one-line confirmation visible to you.
- **`on-edit.sh`** (`PostToolUse`, matcher `Write|Edit|MultiEdit`), when Claude itself edits your instructions, it reminds the agent to ask you before broadcasting to other sessions.

The "version" is a hash of `CLAUDE.md` + every `rules/*.md` + a nonce file. Daily logs / memory are deliberately excluded (they change constantly).

## Install

Requirements: `bash`, `jq`, and one of `md5` / `md5sum` / `shasum`.

```bash
git clone https://github.com/rafiimanggala/claude-sop-refresh
cd claude-sop-refresh
./install.sh            # copies files, prints the settings.json snippet
# or:
./install.sh --register # also merges the hooks into ~/.claude/settings.json (backs it up first)
```

`install.sh` copies the hooks to `~/.claude/hooks/sop-refresh/` and the CLI to `~/.local/bin/sop-refresh`. With `--register` it adds the three hooks to `~/.claude/settings.json` (idempotent, with a timestamped backup). Start a new session afterward so the hooks load.

### Manual hook registration

If you'd rather edit `~/.claude/settings.json` yourself, merge this into your `"hooks"` object:

```json
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
```

## Usage

Most of the time you do nothing, just edit `CLAUDE.md` and every session refreshes on its next prompt.

```bash
sop-refresh            # force a re-broadcast even if no file changed, list live sessions
sop-refresh --status   # just list live sessions and when each will refresh
sop-refresh --note "tightened the git rules"   # bump + leave a note in the log
```

Example:

```
$ sop-refresh --status
ℹ status only (no bump)

Live sessions:
  • pid=15088  status=idle     idle 46m         51b6a4e5  /Users/you/project-a
      ↳ refresh on the next prompt
  • pid=28509  status=busy     active 1m ago    f9ced7cd  /Users/you/project-b
      ↳ waits until the task finishes → refresh on the next turn

Total live=2, busy=1. Refresh is lazy (applied at a turn boundary, never interrupting a task).
```

## Security & trust

- **What gets injected is your own `CLAUDE.md` + `rules/`**, the same files Claude already loads at startup. The SUPERSEDES banner just tells the model to prefer the fresh copy. This is the same trust boundary you already grant your instructions; it is **not** a new prompt-injection vector.
- **Corollary:** don't put untrusted, third-party-authored content in `CLAUDE.md` / `rules/`. If you sync those from a shared repo, the banner will reinforce whatever they contain, that's true of native loading too, but worth stating.
- The hooks only ever write under `~/.claude` (a version marker per session, a nonce, a small log). `session_id` from the hook payload is validated (`[A-Za-z0-9_-]` only) before it's used in any path, so a malformed id can't escape that directory.
- Everything is plain Bash you can read in a few minutes. No network calls, no telemetry.

## Limitations

- Injected context is **additive**: the fresh `CLAUDE.md` is appended and marked as superseding, but the original copy still sits earlier in the context window. In practice the model follows the latest, but it isn't a hard replacement.
- Hook output is not replayed on `--resume` / `--continue`, so a resumed session re-checks on its next live prompt rather than replaying the banner.
- Designed for instructions that *evolve* (SOPs, rules), not for session-local preferences you don't want pushed everywhere.

## License

MIT © 2026 Rafii Manggala Japamel
