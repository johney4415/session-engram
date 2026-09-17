---
name: session-engram
description: Find, resume, inspect or clean up past Claude Code and Codex sessions on this machine using the `session-engram` CLI. Use when the user refers to an earlier session, conversation or transcript ("the session where we fixed the redis limit", "上次那個 session", "resume that conversation", "what did I work on yesterday"), asks which sessions are eating disk space, or asks to delete old transcripts.
---

# Session Engram

`session-engram` indexes every Claude Code transcript in `~/.claude/projects` and
every Codex rollout in `~/.codex/sessions`, and titles each one by the first
prompt the user actually typed. Use it instead of reading transcript files by
hand — parsing those directories directly is slow and the raw JSONL has no
usable title.

Every command reads local files and prints to stdout. Nothing leaves the machine.

## Before anything else

Check the CLI is installed:

```sh
command -v session-engram || ls "$HOME/.local/bin/session-engram"
```

If it is missing, build and install it from the plugin's own checkout, then use
the absolute path if `~/.local/bin` is not on `PATH`:

```sh
"$CLAUDE_PLUGIN_ROOT/scripts/install.sh" --cli-only
```

## Reading sessions

Always add `--plain` or `--json`. Without them the browser takes over when a
terminal is attached, and the human-readable listing writes its summary to
stderr.

```sh
session-engram list --plain --limit 20              # newest first
session-engram list --json --limit 5                # full records
session-engram list --plain --search "redis limit"  # every word must match
session-engram list --plain --content 16942         # also read the transcripts
session-engram list --plain --sort largest -n 10    # disk hogs
session-engram list --plain --claude                # one provider only
```

`--plain` prints one tab-separated line per session:

```
<session-id>  <provider>  <updated-at>  <turns>  <size>  <directory>  <title>
```

`--search` matches the title, the directory and the id, and every word has to
match, so it only finds what the user can spell. Add `--content` to also match
words inside the transcripts themselves — a PR number, a table name or an error
string that was only ever pasted mid-conversation. It reads every transcript
(a second or two), and matching is a plain case-insensitive substring check over
the whole file, so assistant output and tool results count too. `--sort` takes
`newest|oldest|largest|busiest`, and `--no-archived` hides archived Codex
sessions.

## Finding a session by description

When the user describes what happened in a session rather than its title, do the
matching yourself in two passes. A title is only the first thing they typed, so
a session on the right subject often has an unrelated title — the titles alone
are not enough to answer with.

1. **Shortlist from the metadata.** `session-engram list --plain --limit 60`,
   narrowed by `--claude`/`--codex` or a `--search` word if the description
   gives you one that will actually appear. When the description carries an
   exact token — an id, a PR number, an error message — try
   `--content <token>` first; it finds the session even when the token never
   made it into the title. Read the titles, directories and dates, and pick
   the handful that could plausibly be it.
2. **Read what they typed.** For each candidate, `session-engram prompts <id>`
   prints the prompts the user typed in that session, one per line — the topic
   of the session in their own words. `--limit <n>` takes more or fewer,
   `--json` gives an array.
3. **Answer with the reason.** Name the session that matches and say which
   prompt made you sure, then offer `/sessions-resume <id>`.

`prompts` reads only the user's own turns, skipping harness-injected context;
assistant replies, tool calls and file contents are never read.

## Resuming

`session-engram resume <id>` prints the command that reopens a session; it does
not resume it. That is the right behaviour here — resuming replaces the running
process, which would kill this Claude Code session.

```sh
session-engram resume 1a2b3c4d          # prints: cd <dir> && claude --resume <id>
session-engram resume 1a2b3c4d --copy   # puts that line on the clipboard
```

Give the user the printed line to run themselves, or offer `--copy`. Never
`eval` it and never run `claude --resume` or `codex resume` yourself.

Ids are matched by prefix, so the eight characters a listing shows are enough. A
prefix that matches more than one session is reported rather than guessed at.

## Deleting

`delete` moves transcripts to the Trash. It asks for confirmation on stdin,
which a tool call has no way to answer, so:

1. Show the user exactly which sessions would go, from a `list --plain` run.
2. Get their explicit go-ahead.
3. Only then run it with `--yes`.

```sh
session-engram delete 1a2b3c4d 5e6f7a8b --yes
```

Never pass `--permanent` unless the user asks for an unrecoverable delete in so
many words — it is the one way this tool destroys a transcript. Deleting drops
the parse cache, so the next listing rescans.

## Other

- `session-engram refresh` rebuilds the parse cache; only needed when a listing
  looks stale.
- `session-engram help` lists every command and option.
- `session-engram browse` is the interactive full-screen browser. It is for a
  human at a terminal, not for a tool call; without a TTY it degrades to the
  plain listing.
