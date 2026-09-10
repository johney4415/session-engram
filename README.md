# Agent Sessions

A macOS menu bar app and CLI for the coding-agent sessions you have already finished.
It reads the transcripts Claude Code and Codex leave on disk, gives each one a
readable title, and lets you pick several at once to copy their resume commands or
move them to the Trash.


## What it does

- Indexes every Claude Code transcript in `~/.claude/projects` and every Codex
  rollout in `~/.codex/sessions` (including `archived_sessions`).
- Titles each session from the first prompt a person actually typed, skipping the
  context the harness injects. Codex sessions use the thread name Codex recorded.
- Folds the several rollout files Codex writes for one resumed thread into a single
  row, so a session is listed once and deleted once.
- Counts real user turns and the disk each session occupies.
- Multi-select, then copy one `cd … && claude --resume …` line per session, or move
  them all to the Trash.
- Caches parse results, so after the first scan the list opens instantly.
- Local files only. No network, no telemetry.

## Requirements

- macOS 14 or newer
- Xcode 16 or a compatible Swift 6 toolchain
- Claude Code and/or Codex CLI

## Install

```sh
make install
```

That builds in release mode, puts `agent-sessions` in `~/.local/bin`, and creates
`~/Applications/Agent Sessions.app`. Open the app once and it stays in the menu bar.

To remove everything: `./scripts/uninstall.sh`

## Menu bar

Click the clock icon to open the list.

| Action | How |
| --- | --- |
| Filter | Type in the search box — every word must match the title, directory or id |
| Narrow to one CLI | The All / Claude / Codex picker |
| Select | Click any row; click again to deselect |
| Copy resume commands | Select rows, then **Copy resume** |
| Delete | Select rows, then **Trash** and confirm |
| Per-session actions | Right-click a row: copy the id, or reveal the transcript in Finder |

Deleted transcripts go to the Trash, so a wrong click is recoverable.

## CLI

The same binary is a CLI whenever it gets arguments.

```sh
agent-sessions list                          # newest first
agent-sessions list --codex --limit 20
agent-sessions list --search "export preview"
agent-sessions list --sort largest --limit 10   # find what is eating disk
agent-sessions resume 1a2b3c4d               # print the resume command
agent-sessions delete 1a2b3c4d 5e6f7a8b      # move to Trash, with confirmation
agent-sessions refresh                       # rebuild the cache
agent-sessions help
```

Jump straight back into a session:

```sh
eval "$(agent-sessions resume 1a2b3c4d)"
```

Pick sessions interactively and delete them:

```sh
agent-sessions list --plain | fzf -m | cut -f1 | xargs agent-sessions delete
```

`--plain` prints one tab-separated line per session
(`id · provider · timestamp · turns · size · directory · title`), and `--json`
prints the full records.

## How sessions are read

| | Claude Code | Codex |
| --- | --- | --- |
| Location | `~/.claude/projects/<escaped-cwd>/<uuid>.jsonl` | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| Resume id | The file name | `session_meta.session_id` |
| Working directory | The `cwd` field on any line | `session_meta.cwd` |
| Title | First typed prompt | `session_index.jsonl` thread name, else first typed prompt |
| Also removed | `<uuid>/subagents/` | Other rollout files for the same thread |

Titles are a heuristic over the transcript, so a session that opened with a pasted
traceback is titled with that traceback — which is usually still how you remember it.

The parse cache lives in
`~/Library/Caches/dev.johney4415.agent-sessions/index.json` and is keyed by each
file's size and modification date. Delete it, or run `agent-sessions refresh`, to
rebuild from scratch.

## Development

```sh
make build
make test
```

## License

MIT
