# Agent Sessions

Your finished Claude Code and Codex sessions, in one list you can search, resume
and clean up — from the menu bar, the terminal, or inside Claude Code itself.

![The Agent Sessions list open in the macOS menu bar](docs/menu-bar.png)

It reads the transcripts already on disk — `~/.claude/projects` and
`~/.codex/sessions` — and titles each one by the first prompt you typed, not the
context the harness injected. Everything stays local except `ask`.

## Install

Needs macOS 14+, a Swift 6 toolchain (Xcode 16) and Claude Code or Codex.

```sh
git clone https://github.com/johney4415/agent-sessions.git
cd agent-sessions && make install
```

That puts the CLI at `~/.local/bin/agent-sessions` and the menu bar app at
`~/Applications/Agent Sessions.app`. If the CLI is not found:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
```

`make install-cli` skips the app. `git pull && make install` updates.
`./scripts/uninstall.sh` removes everything but your transcripts.

### As a Claude Code plugin

```
/plugin marketplace add johney4415/agent-sessions
/plugin install agent-sessions@agent-sessions
```

| Command | |
| --- | --- |
| `/sessions [words]` | List sessions, filtered by word, provider or size |
| `/sessions-ask <description>` | Find the one you remember by what happened in it |
| `/sessions-resume <id>` | Print the line that reopens it |
| `/sessions-clean` | Show what is eating disk, delete what you pick |

Plain language works too — "which session was the redis one". Claude hands you
the resume command rather than running it, since resuming replaces the process.
The plugin calls the CLI, so install that as well.

## Use it

**Menu bar** — click the list icon. Search filters on title, directory and id;
click rows to select, then **Copy resume** or **Trash**. Right-click a row to
copy its id or reveal the transcript. The first open scans; after that it is
cached, and the circular arrow rescans.

**Terminal** — `agent-sessions` with no arguments opens the same list
full-screen.

| Key | |
| --- | --- |
| `↑` `↓` / `k` `j` | Move |
| `space` `a` `x` | Select the row / everything shown / nothing |
| `/` | Filter by word |
| `?` | Describe what you remember, let claude or codex find it |
| `enter` | Resume under the cursor, in this terminal |
| `c` `d` | Copy the resume command / move to the Trash after a `y` |
| `s` `f` `r` | Cycle sort / cycle provider / rescan |
| `esc` `q` | Drop the search, then the filter, then quit / quit |

**Scripts**

```sh
agent-sessions list --sort largest -n 10     # what is eating disk
agent-sessions list --codex --search redis
eval "$(agent-sessions resume 1a2b3c4d)"     # jump straight back in
agent-sessions delete 1a2b3c4d --yes         # move to Trash
agent-sessions list --plain | fzf -m | cut -f1 | xargs agent-sessions delete
```

Ids match by prefix, so the eight characters the list shows are enough; an
ambiguous prefix is reported rather than guessed at. `--plain` gives one
tab-separated line per session, `--json` the full records. `delete --permanent`
is the one way this tool removes a transcript unrecoverably.
`agent-sessions help` lists everything.

## Finding one by description

Word search only finds what you can spell. `ask` is for the sessions you
remember by what happened in them.

```sh
agent-sessions ask "the one where we chased the redis memory limit"
agent-sessions ask --agent codex --limit 3 "清理磁碟空間那次"
```

It shortlists from the metadata, then reads the prompts of the shortlist and
ranks what actually matches — a title is only the first thing you typed. Matches
open in the browser, sorted by relevance; `--plain` and `--json` print them.

This is the one command that is not local. It runs `claude -p` or `codex exec`
under the login you already have, so it needs no API key, and what it sends goes
wherever that agent already sends your prompts: one metadata line per session,
then the prompts *you typed* in the dozen it shortlisted. Assistant replies, tool
calls and file contents are never read. `--dry-run` prints the prompt and sends
nothing. Each search leaves one short session of its own.

MIT licensed.
