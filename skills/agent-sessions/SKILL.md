---
name: agent-sessions
description: Find, resume, inspect or clean up past Claude Code and Codex sessions on this machine using the `agent-sessions` CLI. Use when the user refers to an earlier session, conversation or transcript ("the session where we fixed the redis limit", "上次那個 session", "resume that conversation", "what did I work on yesterday"), asks which sessions are eating disk space, or asks to delete old transcripts.
---

# Agent Sessions

`agent-sessions` indexes every Claude Code transcript in `~/.claude/projects` and
every Codex rollout in `~/.codex/sessions`, and titles each one by the first
prompt the user actually typed. Use it instead of reading transcript files by
hand — parsing `~/.claude/projects` directly is slow and the raw JSONL has no
usable title.

## Before anything else

Check the CLI is installed:

```sh
command -v agent-sessions || ls "$HOME/.local/bin/agent-sessions"
```

If it is missing, build and install it from the plugin's own checkout, then use
it via the absolute path if `~/.local/bin` is not on `PATH`:

```sh
"$CLAUDE_PLUGIN_ROOT/scripts/install.sh" --cli-only
```

## Reading sessions

Always add `--plain` or `--json`. Without them the browser takes over when a
terminal is attached, and the human-readable listing writes its summary to
stderr.

```sh
agent-sessions list --plain --limit 20              # newest first
agent-sessions list --json --limit 5                # full records
agent-sessions list --plain --search "redis limit"  # every word must match
agent-sessions list --plain --sort largest -n 10    # disk hogs
agent-sessions list --plain --claude                # one provider only
```

`--plain` prints one tab-separated line per session:

```
<session-id>  <provider>  <updated-at>  <turns>  <size>  <directory>  <title>
```

`--search` matches the title, the directory and the id, and every word has to
match, so it only finds what the user can spell. `--sort` takes
`newest|oldest|largest|busiest`, and `--no-archived` hides archived Codex
sessions.

## Finding a session by description

When the user describes what happened in a session rather than its title, use
`ask` — it hands the judgement to the `claude` or `codex` CLI:

```sh
agent-sessions ask --plain "the one where we chased the redis memory limit"
agent-sessions ask --json --limit 3 --agent codex "清理磁碟空間那次"
```

Output columns are `id, provider, updated-at, directory, title, reason`, ranked
by relevance, with the agent's reason for each match.

This is the one command that leaves the machine: it spawns `claude -p` or
`codex exec` under the login the user already has, sending one metadata line per
session plus the prompts the *user* typed in the dozen it shortlists. Assistant
replies, tool calls and file contents are never read. It also takes tens of
seconds and leaves behind a short session of its own titled
`agent-sessions search: …`.

So: reach for `list --search` first, and only fall back to `ask` when word
search cannot express what the user remembers. Mention that `ask` calls out to
the agent CLI before running it on a fresh request. `--dry-run` prints the
prompt and sends nothing.

## Resuming

`agent-sessions resume <id>` prints the command that reopens a session; it does
not resume it. That is the right behaviour here — resuming replaces the running
process, which would kill this Claude Code session.

```sh
agent-sessions resume 1a2b3c4d          # prints: cd <dir> && claude --resume <id>
agent-sessions resume 1a2b3c4d --copy   # puts that line on the clipboard
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
agent-sessions delete 1a2b3c4d 5e6f7a8b --yes
```

Never pass `--permanent` unless the user asks for an unrecoverable delete in so
many words — it is the one way this tool destroys a transcript. Deleting drops
the parse cache, so the next listing rescans.

## Other

- `agent-sessions refresh` rebuilds the parse cache; only needed when a listing
  looks stale.
- `agent-sessions help` lists every command and option.
- `agent-sessions browse` is the interactive full-screen browser. It is for a
  human at a terminal, not for a tool call; without a TTY it degrades to the
  plain listing.
