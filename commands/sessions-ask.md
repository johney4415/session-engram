---
description: Find a past session from a vague description of what happened in it
argument-hint: "<what you remember about the session>"
allowed-tools: Bash(session-engram:*), Bash(command -v session-engram)
---

Find the session the user is describing: `$ARGUMENTS`

If the description is empty, ask what they remember about the session and stop.

1. **Try the word search first.** `session-engram list --plain --search "<the
   distinctive words>" --limit 10`. If the description contains a word that
   would really appear in a title, directory or id, this answers it outright.
2. **Otherwise shortlist by metadata.** `session-engram list --plain --limit 60`
   and read the titles, directories and dates. Narrow to the handful that could
   plausibly be the one. Add `--claude`/`--codex` if the user said which.
3. **Read what they typed.** For each candidate, `session-engram prompts <id>`
   prints the prompts the user typed in that session. Titles are only the first
   thing typed, so this is the pass that actually decides it.
4. **Answer.** Name the session, quote the prompt that made you sure, and offer
   `/sessions-resume <id>`. If two are close, show both rather than guessing.

You are the one doing the matching — there is no agent to hand it off to, and
nothing here leaves the machine. Don't read the raw transcripts under
`~/.claude/projects` yourself; `prompts` already extracts the user's turns and
skips the harness-injected context.
