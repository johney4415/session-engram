---
description: List past Claude Code and Codex sessions, optionally filtered
argument-hint: "[words to filter by] [--claude|--codex] [--sort largest]"
allowed-tools: Bash(agent-sessions:*), Bash(command -v agent-sessions)
---

List the user's past agent sessions with `agent-sessions`.

Arguments, if any: `$ARGUMENTS`

1. Run `agent-sessions list --plain --limit 20`, adding the arguments above.
   Bare words go through `--search` (every word has to match the title, the
   directory or the id); flags such as `--claude`, `--codex`, `--sort largest`
   or `-n 30` pass straight through.
2. Present the result as a table: short id (first 8 characters), when it was
   last touched, provider, turns, size, directory, title.
3. Close with the total count and disk size, and offer the obvious next steps —
   `/sessions-resume <id>` to reopen one, `/sessions-ask` if word search missed
   it, `/sessions-clean` if the sizes look alarming.

If nothing matched, say so and suggest `/sessions-ask` rather than guessing at
other search words.
