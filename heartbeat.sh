#!/usr/bin/env bash
# Heartbeat hook for Claude Code (UserPromptSubmit).
# Every N prompts, re-injects the most important rules into the active session
# so the model doesn't drift mid-conversation.
#
# Stdout from this hook is injected into the conversation as a system reminder.
# Exit 0 = inject (if stdout non-empty), no-op otherwise.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)"

STATE_DIR="$HOME/.claude/state/heartbeat"
mkdir -p "$STATE_DIR"
COUNTER_FILE="$STATE_DIR/$SESSION_ID.count"

# Tunable: gentle reminder every N prompts.
NUDGE_EVERY=8

# Bump counter.
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Fire only on the Nth, 2Nth, 3Nth... prompt.
if [ $((COUNT % NUDGE_EVERY)) -ne 0 ]; then
  exit 0
fi

cat <<EOF
<heartbeat prompt="$COUNT">
HEARTBEAT — Reminder before responding:
- Short replies (1–4 sentences) unless analysis was requested.
- NEVER read, echo, cat, or grep the VALUE of any secret, API key, token, password, or credential. NEVER scan the filesystem for leaked secrets unless explicitly asked for a security audit in THIS conversation.
- NEVER mention or act on info from OTHER projects. Current working directory is the only project that matters.
- No guessing — verify before claiming. No workarounds — root-cause and idiomatic fix only.
- Re-check ~/.claude/CLAUDE.md ZERO TOLERANCE rules AND your MEMORY.md feedback entries.
</heartbeat>
EOF

# Log to a file you can tail any time: ~/.claude/state/heartbeat/log
echo "$(date '+%Y-%m-%d %H:%M:%S')  session=$SESSION_ID  prompt=$COUNT" >> "$STATE_DIR/log"

exit 0
