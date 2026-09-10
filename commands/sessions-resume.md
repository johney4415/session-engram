---
description: Get the command that reopens a past session
argument-hint: "<session id prefix, or what you remember about it>"
allowed-tools: Bash(agent-sessions:*), Bash(command -v agent-sessions)
---

Work out how to reopen the session the user means: `$ARGUMENTS`

1. If the argument looks like a session id (hex, at least 4 characters), run
   `agent-sessions resume <id>` — a prefix is enough. Otherwise find it first
   with `agent-sessions list --plain --search "$ARGUMENTS" --limit 10`, and if
   several sessions could be it, show them and ask which one.
2. Give the user the printed `cd … && claude --resume …` line to run
   themselves, in a copyable block. Offer `agent-sessions resume <id> --copy` to
   put it on the clipboard.

Do not run the resume command yourself and do not `eval` it: it replaces the
running process, which would kill this Claude Code session. Printing the line is
the whole job.
