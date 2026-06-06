# heartbeat-hook

A tiny [Claude Code](https://docs.claude.com/en/docs/claude-code) `UserPromptSubmit` hook that periodically re-injects your most important rules into the active session so the model doesn't drift halfway through a long conversation.

## Why

Long sessions cause AI drift. Halfway through a conversation the model "forgets" rules that were front-and-center at the start — short replies, no secrets in chat, no cross-project leakage, no guessing. By the time you notice, an API key has been echoed into the transcript, or a workaround has been merged.

This hook is a heartbeat. Every few prompts it injects a one-liner reminder. As the transcript grows, the reminder escalates from a gentle nudge to a hard pre-compaction warning.

## How it works

The hook runs on every `UserPromptSubmit` event. It receives the session's `transcript_path` on stdin, then uses two signals:

1. **Prompt counter** — gentle nudge every N prompts (default 8). Per-session state in `~/.claude/state/heartbeat/<session_id>.count`.
2. **Transcript size** — measured with `wc -c` on the transcript file. Bytes aren't tokens, but it's a close-enough proxy for context fill. Three tiers (default 200KB / 500KB / 900KB), each more urgent than the last. A tier only fires the first time it's crossed in a session.

Strongest signal wins. The reminder is emitted to stdout, which Claude Code injects into the conversation as a system reminder before the model responds.

## Install

1. Drop `heartbeat.sh` somewhere persistent (e.g. `~/.claude/hooks/heartbeat.sh`) and make it executable:
   ```sh
   mkdir -p ~/.claude/hooks
   cp heartbeat.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/heartbeat.sh
   ```
2. Wire it up in `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "bash ~/.claude/hooks/heartbeat.sh"
             }
           ]
         }
       ]
     }
   }
   ```
3. Restart Claude Code.

Requires `jq` on `PATH` (the script prepends `/opt/homebrew/bin` and `/usr/local/bin` so Homebrew installs work in non-interactive hook shells).

## Tuning

Open `heartbeat.sh` and edit the constants at the top:

```sh
NUDGE_EVERY=8           # gentle reminder every N prompts
SIZE_TIER1=200000       # ~200KB transcript → light nudge
SIZE_TIER2=500000       # ~500KB transcript → strong reminder
SIZE_TIER3=900000       # ~900KB transcript → pre-compaction warning
```

The reminder text is inline in the script — edit it to match the rules YOU want the model to re-read. Mine emphasises: no echoing secrets, no cross-project leakage, no guessing, short replies. Yours will be different.

## State

Per-session counters and tier-tracking files live in `~/.claude/state/heartbeat/`. Safe to delete any time — sessions start fresh.

## License

MIT.
