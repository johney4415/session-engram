#!/bin/sh
set -eu

bin_dir=${AGENTSESSIONS_BIN_DIR:-"$HOME/.local/bin"}
app_dir=${AGENTSESSIONS_APP_DIR:-"$HOME/Applications"}
cache_dir="$HOME/Library/Caches/dev.johney4415.agent-sessions"

osascript -e 'quit app "Agent Sessions"' 2>/dev/null || true
rm -f "$bin_dir/agent-sessions"
rm -rf "$app_dir/Agent Sessions.app"
rm -rf "$cache_dir"

printf 'Removed the CLI, the app bundle and the parse cache.\n'
printf 'Session transcripts were not touched.\n'
