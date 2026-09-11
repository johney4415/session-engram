# Contributing

## Build and test

```sh
make build     # swift build
make test      # swift test, 26 tests, no network and no fixtures on your real disk
make install   # the CLI at ~/.local/bin and the menu bar app in ~/Applications
```

Needs macOS 14 or newer and a Swift 6 toolchain (Xcode 16). `make install-cli`
skips the app bundle when you only want the binary.

## Where things are

```
ClaudeScanner / CodexScanner   one transcript directory each -> SessionRecord
SessionMerger                  both providers into one list
SessionIndex                   the parse cache under ~/Library/Caches
TitleBuilder                   picks the title from what the person typed
SessionExcerpt                 pulls those prompts out, behind `prompts`
SessionQuery                   filter and sort
CLI / InteractiveBrowser       the terminal, raw mode drawing and all
SessionListModel / ...View     the menu bar app
```

The two scanners are the part worth knowing: they walk every transcript on
every scan, so anything added there costs time on a machine with hundreds of
sessions. Both read only the turns a person wrote — the harness pushes context
through the user role, and counting or titling from that is the bug this has
already had once.

## House rules

- **Nothing leaves the machine.** Every command reads local files and writes to
  stdout. No telemetry, no network calls, no API keys. A change that sends
  anything anywhere needs to justify itself in the pull request.
- **Comments in English**, and only where the code cannot say it itself.
- **Match the surrounding code.** Same naming, same comment density, same
  idiom.
- **Tests for anything that parses.** Transcript formats drift; the scanner and
  title tests are what catch it. Fixtures are written to a temp directory, never
  to your real `~/.claude`.
- **One concern per commit.** A rename and a bug fix are two commits.
- **Never invent a session id or path in a fixture from your own machine.** Use
  obviously made up values — this repo is public and transcripts carry client
  and employer names.

## Pull requests

Say what breaks if the change is wrong. `make test` has to pass, and CI runs
the same thing plus the install script on a clean macOS runner.

Destructive paths deserve extra care in review: `delete --permanent` is the one
way this tool removes a transcript unrecoverably, and `resume` prints a command
the README shows under `eval`, so anything interpolated into it has to survive
a shell.
