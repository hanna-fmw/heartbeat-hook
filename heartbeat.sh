#!/usr/bin/env bash
# Heartbeat hook for Claude Code (UserPromptSubmit).
# Periodically re-injects the most critical rules into the session so the
# active model doesn't drift mid-conversation. Two signals combined:
#   1. Prompt counter — gentle nudge every N prompts.
#   2. Transcript size — escalating reminder as context fills up.
#
# Stdout from this hook is injected into the conversation as a system reminder.
# Exit 0 = inject, exit non-zero or empty stdout = no-op.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

INPUT="$(cat)"
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)"

STATE_DIR="$HOME/.claude/state/heartbeat"
mkdir -p "$STATE_DIR"
COUNTER_FILE="$STATE_DIR/$SESSION_ID.count"
TIER_FILE="$STATE_DIR/$SESSION_ID.tier"

# Tunables.
NUDGE_EVERY=8           # gentle reminder every N prompts
SIZE_TIER1=200000       # ~200KB transcript → light nudge
SIZE_TIER2=500000       # ~500KB transcript → strong reminder
SIZE_TIER3=900000       # ~900KB transcript → pre-compaction warning

# Bump counter.
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Measure transcript size (rough proxy for context fill).
SIZE=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  SIZE=$(wc -c < "$TRANSCRIPT_PATH" | tr -d ' ')
fi

# Determine the highest tier crossed so far this session.
LAST_TIER=0
[ -f "$TIER_FILE" ] && LAST_TIER=$(cat "$TIER_FILE" 2>/dev/null || echo 0)
TIER=0
if   [ "$SIZE" -ge "$SIZE_TIER3" ]; then TIER=3
elif [ "$SIZE" -ge "$SIZE_TIER2" ]; then TIER=2
elif [ "$SIZE" -ge "$SIZE_TIER1" ]; then TIER=1
fi
[ "$TIER" -gt "$LAST_TIER" ] && echo "$TIER" > "$TIER_FILE"

# Decide whether to fire.
FIRE_COUNTER=0
FIRE_TIER=0
[ $((COUNT % NUDGE_EVERY)) -eq 0 ] && FIRE_COUNTER=1
[ "$TIER" -gt "$LAST_TIER" ] && FIRE_TIER=1

if [ "$FIRE_COUNTER" -eq 0 ] && [ "$FIRE_TIER" -eq 0 ]; then
  exit 0
fi

# Build the reminder. Strongest signal wins.
{
  echo "<heartbeat prompt=\"$COUNT\" transcript_bytes=\"$SIZE\" tier=\"$TIER\">"
  if [ "$TIER" -ge 3 ]; then
    cat <<'EOF'
CRITICAL HEARTBEAT — context window is nearly full. Before responding:
1. Re-read ~/.claude/CLAUDE.md, especially every ZERO TOLERANCE section.
2. Re-read the project's CLAUDE.md if one exists.
3. NEVER read, echo, cat, grep, or surface ANY secret/API key/token/password value. Do not scan the filesystem for leaked secrets unless the user explicitly asked for a security audit in THIS conversation.
4. Stay strictly on-task. Do not drift, do not start new work, do not "helpfully" explore adjacent files.
5. Keep replies short: 1–4 sentences unless the user asked for analysis.
EOF
  elif [ "$TIER" -ge 2 ]; then
    cat <<'EOF'
HEARTBEAT (strong) — long session, drift likely. Before responding:
- NEVER print/echo/cat any secret, API key, token, password, or credential value. Never scan the filesystem for leaked secrets without an explicit user request.
- NEVER mention or act on info from OTHER projects. Current working directory is the only project that matters.
- NO workarounds, NO guessing, NO long replies. Short and direct.
- Re-check ~/.claude/CLAUDE.md ZERO TOLERANCE rules before any risky action (commit, push, MCP call, file delete, env read).
EOF
  elif [ "$TIER" -ge 1 ]; then
    cat <<'EOF'
HEARTBEAT — Reminder: short replies (1–4 sentences). No secrets in chat. No cross-project leakage. No guessing — verify before claiming. No workarounds — root-cause and idiomatic fix only.
EOF
  else
    cat <<'EOF'
HEARTBEAT — Reminder: short replies. NEVER print/echo any secret, API key, token, or credential value. NEVER scan for leaked secrets unless explicitly asked. Stay on-task.
EOF
  fi
  echo "</heartbeat>"
}

exit 0
