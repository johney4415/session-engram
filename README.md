# Session Engram

Your finished Claude Code and Codex sessions, in one list you can search, resume
and clean up — from the menu bar, the terminal, or inside Claude Code itself.

![The Session Engram list open in the macOS menu bar](docs/menu-bar.png)

It reads the transcripts already on disk — `~/.claude/projects` and
`~/.codex/sessions` — and titles each one by the first prompt you typed, not the
context the harness injected. Every command reads local files and writes to your
terminal; nothing leaves the machine and there is no telemetry.

## Install

Needs macOS 14+, a Swift 6 toolchain (Xcode 16) and Claude Code or Codex.

```sh
git clone https://github.com/johney4415/session-engram.git
cd session-engram && make install
```

That puts the CLI at `~/.local/bin/session-engram` and the menu bar app at
`~/Applications/Session Engram.app`. If the CLI is not found:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
```

`make install-cli` skips the app. `git pull && make install` updates.
`./scripts/uninstall.sh` removes everything but your transcripts.

### As a Claude Code plugin

```
/plugin marketplace add johney4415/session-engram
/plugin install session-engram@session-engram
```

| Command | |
| --- | --- |
| `/sessions [words]` | List sessions, filtered by word, provider or size |
| `/sessions-ask <description>` | Find the one you remember by what happened in it |
| `/sessions-resume <id>` | Print the line that reopens it |
| `/sessions-clean` | Show what is eating disk, delete what you pick |

Plain language works too — "which session was the redis one". Word search only
finds what you can spell, so for those Claude shortlists on the metadata and
then reads the prompts you typed in each candidate, which is what tells apart
two sessions on the same subject. It hands you the resume command rather than
running it, since resuming replaces the process. The plugin calls the CLI, so
install that as well.

## Use it

**Menu bar** — click the list icon. Search filters on title, directory and id;
click rows to select, then **Copy resume** or **Trash**. Right-click a row to
copy its id or reveal the transcript. The first open scans; after that it is
cached, and the circular arrow rescans.

**Terminal** — `session-engram` with no arguments opens the same list
full-screen.

| Key | |
| --- | --- |
| `↑` `↓` / `k` `j` | Move |
| `space` `a` `x` | Select the row / everything shown / nothing |
| `/` | Filter by word |
| `enter` | Resume under the cursor, in this terminal |
| `c` `d` | Copy the resume command / move to the Trash after a `y` |
| `s` `f` `r` | Cycle sort / cycle provider / rescan |
| `esc` `q` | Drop the search, then the filter, then quit / quit |

**Scripts**

```sh
session-engram list --sort largest -n 10     # what is eating disk
session-engram list --codex --search redis
session-engram prompts 1a2b3c4d              # the prompts you typed in one session
eval "$(session-engram resume 1a2b3c4d)"     # jump straight back in
session-engram delete 1a2b3c4d --yes         # move to Trash
session-engram list --plain | fzf -m | cut -f1 | xargs session-engram delete
```

Ids match by prefix, so the eight characters the list shows are enough; an
ambiguous prefix is reported rather than guessed at. `--plain` gives one
tab-separated line per session, `--json` the full records. `delete --permanent`
is the one way this tool removes a transcript unrecoverably.
`session-engram help` lists everything.

## Finding one by description

Word search only finds what you can spell. For the sessions you remember by what
happened in them, `prompts` prints what you typed in one session:

```sh
session-engram prompts 1a2b3c4d
session-engram prompts 1a2b3c4d --limit 20 --json
```

A title is only the first thing you typed, so a session on the right subject
often has an unrelated title — the prompts are what tell two of them apart.
Shortlist with `list`, then read the candidates with `prompts`. Inside Claude
Code, `/sessions-ask` does both passes for you.

Only your own turns are read, and the harness-injected context is skipped;
assistant replies, tool calls and file contents are never touched.

MIT licensed. Building on it: [CONTRIBUTING.md](CONTRIBUTING.md).
