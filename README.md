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
- An interactive terminal browser as well as the menu bar list: arrows to move,
  space to select, enter to drop straight back into the session.
- Finds a session from a vague description by handing the judgement to the
  `claude` or `codex` CLI you already have installed.
- Caches parse results, so after the first scan the list opens instantly.
- Local files, no telemetry. Nothing leaves the machine unless you run `ask`.

## Requirements

- macOS 14 or newer
- Xcode 16 or a compatible Swift 6 toolchain, to build it
- Claude Code and/or Codex CLI — they write the transcripts this reads, and one of
  them also answers `ask`

## Install

Check the toolchain first — the build needs Swift 6:

```sh
swift --version    # 6.0 or newer
```

Xcode 16 provides it; so does the standalone toolchain from
[swift.org](https://www.swift.org/install/macos/). Then:

```sh
git clone https://github.com/johney4415/agent-sessions.git
cd agent-sessions
make install
```

`make install` builds in release mode and installs two copies of the same binary:

| | Where | What it is |
| --- | --- | --- |
| CLI | `~/.local/bin/agent-sessions` | The browser and the commands |
| App | `~/Applications/Agent Sessions.app` | The menu bar list |

Open the app once and it stays in the menu bar:

```sh
open ~/Applications/Agent\ Sessions.app
```

It has no Dock icon and no window — look for the list icon in the menu bar. The
first scan reads every transcript, so it can take a few seconds on a large
collection; after that the cache makes it instant.

Check the CLI is reachable:

```sh
agent-sessions --version
```

If that says `command not found`, `~/.local/bin` is not on your `PATH`. Add it:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
exec zsh
```

To install somewhere else, set either directory:

```sh
AGENTSESSIONS_BIN_DIR=/usr/local/bin AGENTSESSIONS_APP_DIR=/Applications make install
```

### Keep it in the menu bar after a restart

The installer does not touch your login items. To start it with the machine, add
it in **System Settings → General → Login Items & Extensions → Open at Login**.

### Update

```sh
git pull
make install
```

The app is replaced in place, so quit it from its `⋯` menu first — or just quit
and reopen it afterwards to pick up the new build.

### Uninstall

```sh
./scripts/uninstall.sh
```

That quits the app and removes the CLI, the app bundle and the parse cache at
`~/Library/Caches/dev.johney4415.agent-sessions`. Your session transcripts are
never touched.

## Menu bar

![The Agent Sessions list open in the macOS menu bar](docs/menu-bar.png)

### Opening it, step by step

1. **Launch the app.** `open ~/Applications/Agent\ Sessions.app`, or find
   **Agent Sessions** in Spotlight or Launchpad. Nothing appears to happen: it has
   no Dock icon and no window on purpose.
2. **Find its icon in the menu bar.** Look along the right-hand end for the list
   icon (▤). It sits with the other menu bar apps, in the order macOS gives it.
   If the bar is too crowded to show it, hold **⌘** and drag icons to rearrange
   them, or quit a menu bar app you are not using.
3. **Click the icon.** The list drops down: every Claude Code and Codex session on
   the machine, newest first, with the count and total size in the header.
   The first open scans every transcript and can take a few seconds; later opens
   come from the cache and are instant.
4. **Narrow it down.** Type in the search box — every word has to match the title,
   the directory or the id. The **All / Claude / Codex** buttons pick one CLI, and
   the menu beside them changes the order (newest, oldest, largest, most turns).
5. **Select the sessions you want.** Click a row to tick it, click again to untick.
   The footer keeps a count; **None** clears it, and **⋯ → Select all shown** ticks
   everything the filters left.
6. **Do something with them.** **Copy resume** puts one `cd … && claude --resume …`
   line per selected session on the clipboard, ready to paste into a terminal.
   **Trash** asks to confirm in the footer, then moves the transcripts to the Trash.
7. **Or act on a single row.** Right-click it to copy its resume command, copy its
   session id, or reveal the transcript in Finder.
8. **Close the list** by clicking anywhere outside it. The app stays in the menu
   bar. To shut it down entirely, use **⋯ → Quit Agent Sessions**.

The circular arrow at the top right rescans on demand, for sessions that appeared
after the list was last opened.

### Reference

| Action | How |
| --- | --- |
| Filter | Type in the search box — every word must match the title, directory or id |
| Narrow to one CLI | The All / Claude / Codex picker |
| Reorder | The menu next to the picker: newest, oldest, largest, most turns |
| Select | Click any row; click again to deselect |
| Select everything shown | **⋯ → Select all shown** |
| Copy resume commands | Select rows, then **Copy resume** |
| Delete | Select rows, then **Trash**, then confirm in the footer |
| Per-session actions | Right-click a row: copy the id, or reveal the transcript in Finder |
| Rescan | The circular arrow in the header |
| Quit | **⋯ → Quit Agent Sessions** |

Deleted transcripts go to the Trash, so a wrong click is recoverable.

## Interactive browser

Run the binary with no arguments in a terminal and it opens a full-screen list.

```
agent-sessions
```

```
agent-sessions  197 sessions                     All · Newest · 301.9M
  / to search, ? to describe what you remember
  ───────────────────────────────────────────────────────────────────
❯ ◉ 幫我啟用這個工具
    1a2b3c4d  claude  1m ago      2t     610K   ~/projects/agent-sessions
  ○ stock
    5e6f7a8b  codex   12m ago     564t   54.2M  ~/Documents/Codex/…
  ○ 可以幫我看一下怎麼釋放硬體空間嗎？
    a18e1df8  claude  2026-07-15  2t     401K   ~
  ───────────────────────────────────────────────────────────────────
  1 selected
  ↑↓ move · space select · / search · ? ask · enter resume · c copy …
```

| Key | Action |
| --- | --- |
| `↑` `↓` / `k` `j` | Move the cursor |
| `page up` `page down` | Move a screen at a time; `home` `end` jump to either end |
| `space` | Select the row; `a` selects everything shown, `x` clears |
| `/` | Search — type to filter, `enter` to leave the field |
| `?` | Describe the session you want and let claude or codex find it |
| `enter` | Resume the session under the cursor, in this terminal |
| `c` | Copy the resume command for the selection |
| `d` | Move the selection to the Trash, after a `y` confirmation |
| `s` `f` `r` | Cycle sort, cycle provider, rescan |
| `esc` | Drop the agent's result, then the text filter, then quit |
| `q` / `ctrl-c` | Quit |

`enter` replaces the process with `claude --resume …` (or `codex resume …`) in the
session's own directory, so you land back in the agent rather than in a printed
command. With no selection, `c` and `d` act on the row under the cursor.

The bottom line carries the reason an agent picked the highlighted row, whatever
the last action reported, or the pending Trash confirmation.

The browser needs a terminal: piped or non-interactive runs fall back to `list`.
`agent-sessions browse` opens it explicitly and takes the same filters as `list`.
Set `NO_COLOR` to draw it without colour.

## Searching by description

Word search only finds what you can spell. `ask` is for the sessions you remember
by what happened in them.

```sh
agent-sessions ask "the one where we chased the redis memory limit"
agent-sessions ask --agent codex --limit 3 "清理磁碟空間那次"
```

```
Shortlisting 195 sessions with Claude…
Reading 8 transcripts…
Ranking with Claude…

1. a18e1df8  2026-09-10 11:48  claude  401K   可以幫我看一下怎麼釋放硬體空間嗎？
    ~
    ↳ Directly asks how to free disk space, deletes large tgz files
```

In a terminal the matches open in the browser, sorted by relevance, with the
agent's reason for the highlighted row on the bottom line — so `enter` takes you
straight back into the session it found. `esc` widens back out to every session.
`--plain` and `--json` print instead, and `--json` includes the reason per match.

Two passes, because neither half works alone. The agent first shortlists from the
metadata — title, directory, date, turn count — then reads the prompts of the
sessions it shortlisted and ranks what actually matches. A session about the right
subject often has an unrelated title, and sending every transcript at once is far
too much, so it does both.

| Option | |
| --- | --- |
| `--agent claude\|codex` | Which agent judges. Default: whichever is on PATH, claude first |
| `--limit <n>` | At most n matches (default 8) |
| `--dry-run` | Print the prompt that would be sent, and send nothing |
| `--plain`, `--json` | Print the matches instead of opening the browser |
| `--claude`, `--codex`, `--sort`, `--no-archived` | Narrow the pool before the agent sees it |

### What gets sent, and to whom

This is the one command that is not local. It runs the agent CLI already installed
on the machine — `claude -p` or `codex exec` — under your existing login, so it
needs no API key of its own and what it sends goes wherever that agent already
sends your prompts.

Sent in the first pass: one line per session, holding its title, working directory,
date and turn count. Sent in the second pass: the prompts *you typed* in the dozen
or so sessions it shortlisted, each truncated. Assistant replies, tool calls and
file contents are never read. `--dry-run` prints the first-pass prompt verbatim so
you can see it before anything goes out.

Both agents record a transcript of their own for every run, so each search adds one
short session to the list. They are titled `agent-sessions search: …`, which makes
them easy to spot and delete.

## CLI

The same binary is a CLI in a terminal, and the menu bar app when it is launched
from `Agent Sessions.app`.

```sh
agent-sessions                               # the interactive browser
agent-sessions ask "the redis memory one"    # search by description
agent-sessions browse --codex                # browse Codex sessions only
agent-sessions list                          # print, newest first
agent-sessions list --sort largest -i        # print options, then browse
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

Hand the list to something else — the browser covers picking and deleting, but the
plain output is there for the cases it does not:

```sh
agent-sessions list --plain | fzf -m | cut -f1 | xargs agent-sessions delete
agent-sessions list --json | jq '[.[] | select(.byteCount > 10000000)] | length'
```

`--plain` prints one tab-separated line per session
(`id · provider · timestamp · turns · size · directory · title`); for `ask` it is
`id · provider · timestamp · directory · title · why it matched`. `--json` prints
the full records, and for `ask` each record with the agent's reason beside it.

### Commands

| | |
| --- | --- |
| `browse` (`pick`, `ui`) | The interactive browser. What a bare `agent-sessions` runs |
| `ask <text>` (`find`) | Find a session by description — see above |
| `list` (`ls`) | Print sessions |
| `resume <id>` (`cd`) | Print the command that reopens a session |
| `delete <id>…` (`rm`) | Move sessions to the Trash |
| `refresh` | Rebuild the parse cache |
| `help`, `--version` | |

Ids are matched by prefix, so the eight characters the list shows are enough. A
prefix that matches more than one session is reported rather than guessed at.

### Options

| | |
| --- | --- |
| `--claude`, `--codex` | Only one provider |
| `--search <text>`, `-s` | Every word must match the title, directory or id |
| `--sort <newest\|oldest\|largest\|busiest>` | Order. `newest` by default |
| `--limit <n>`, `-n` | Show at most n sessions |
| `--no-archived` | Hide the Codex sessions that were archived |
| `--interactive`, `-i` | Open `list`'s result in the browser |
| `--plain`, `--json` | Tab-separated lines, or full records |

Inside a command a bare word is a search term, so `agent-sessions list redis` and
`agent-sessions list --search redis` are the same thing. A bare word in place of the
command is not: `agent-sessions redis` is an unknown command, not a search.

`resume` takes `--copy`, which puts the command on the clipboard instead of
printing it. `delete` takes `--yes` (`-y`) to skip the confirmation and
`--permanent` to delete outright rather than moving to the Trash — the one way this
tool removes a transcript unrecoverably.

## How sessions are read

| | Claude Code | Codex |
| --- | --- | --- |
| Location | `~/.claude/projects/<escaped-cwd>/<uuid>.jsonl` | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| Resume id | The file name | `session_meta.session_id` |
| Working directory | The `cwd` field on any line | `session_meta.cwd` |
| Title | First typed prompt | `session_index.jsonl` thread name, else first typed prompt |
| Also removed | The `<uuid>/` directory beside it, where subagent transcripts live | The other rollout files Codex wrote for the same thread |

Titles are a heuristic over the transcript, so a session that opened with a pasted
traceback is titled with that traceback — which is usually still how you remember it.

The parse cache lives in
`~/Library/Caches/dev.johney4415.agent-sessions/index.json` and is keyed by each
file's size and modification date. Delete it, or run `agent-sessions refresh`, to
rebuild from scratch.

## Development

```sh
make build      # swift build
make test       # swift test
```

The debug binary is a CLI in every case, since it is not inside an `.app`:

```sh
.build/debug/agent-sessions browse
.build/debug/agent-sessions ask --dry-run "the redis one"   # sends nothing
```

To try the menu bar UI, `make install` and reopen the app.

## License

MIT
