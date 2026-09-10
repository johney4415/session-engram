---
description: Show which past sessions are eating disk space and delete the ones chosen
argument-hint: "[how many to show] [--claude|--codex]"
allowed-tools: Bash(agent-sessions:*), Bash(command -v agent-sessions)
---

Help the user reclaim the disk their old transcripts are taking.

Arguments, if any: `$ARGUMENTS`

1. Run `agent-sessions list --plain --sort largest -n 15`, honouring a count or
   provider filter from the arguments above.
2. Show them as a table — short id, size, turns, age, directory, title — with
   the total at the bottom. Point out the ones that look safe to drop: large,
   old, few turns, or in a directory that no longer exists.
3. Ask which ones to remove. Do not decide for them.
4. Once they name them, run `agent-sessions delete <ids…> --yes` and report what
   was reclaimed.

The transcripts go to the Trash and can be put back. Only add `--permanent` if
the user explicitly asks for an unrecoverable delete, and confirm that separately
before you do.
