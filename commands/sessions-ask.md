---
description: Find a past session from a vague description, using the claude or codex CLI
argument-hint: "<what you remember about the session>"
allowed-tools: Bash(agent-sessions:*), Bash(command -v agent-sessions)
---

Find the session the user is describing: `$ARGUMENTS`

1. If the description is empty, ask what they remember about the session and
   stop.
2. Try word search first — `agent-sessions list --plain --search "<the
   distinctive words>" --limit 10`. If that already answers it, report those
   matches and skip step 3; it is instant and stays on this machine.
3. Otherwise run `agent-sessions ask --plain "$ARGUMENTS"`. This spawns the
   `claude` or `codex` CLI to do the ranking, takes tens of seconds, and sends
   one metadata line per session plus the prompts the user typed in the dozen it
   shortlists. Say that you are about to do it before you run it.
4. Report the matches in relevance order with the reason given for each, and
   offer `/sessions-resume <id>` for the one they meant.

Add `--agent codex`, `--limit <n>` or a provider filter if the user asked for
them. Use `--dry-run` if they want to see what would be sent without sending it.
