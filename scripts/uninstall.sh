#!/bin/sh
set -eu

bin_dir=${SESSION_ENGRAM_BIN_DIR:-"$HOME/.local/bin"}
app_dir=${SESSION_ENGRAM_APP_DIR:-"$HOME/Applications"}
cache_dir="$HOME/Library/Caches/dev.johney4415.session-engram"

osascript -e 'quit app "Session Engram"' 2>/dev/null || true
rm -f "$bin_dir/session-engram"
rm -rf "$app_dir/Session Engram.app"
rm -rf "$cache_dir"

printf 'Removed the CLI, the app bundle and the parse cache.\n'
printf 'Session transcripts were not touched.\n'
