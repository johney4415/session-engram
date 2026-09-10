#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin_dir=${SESSION_ENGRAM_BIN_DIR:-"$HOME/.local/bin"}
app_dir=${SESSION_ENGRAM_APP_DIR:-"$HOME/Applications"}
app_bundle="$app_dir/Session Engram.app"
cli_only=

# The Claude Code plugin needs the CLI its commands shell out to, not the menu bar app.
for arg in "$@"; do
    case $arg in
        --cli-only) cli_only=1 ;;
        *) printf 'usage: %s [--cli-only]\n' "$0" >&2; exit 2 ;;
    esac
done

cd "$repo_dir"
swift build -c release

mkdir -p "$bin_dir"
cp .build/release/session-engram "$bin_dir/session-engram"
printf 'Installed CLI: %s\n' "$bin_dir/session-engram"

if [ -n "$cli_only" ]; then
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) printf 'Note: %s is not on PATH.\n' "$bin_dir" ;;
    esac
    exit 0
fi

mkdir -p "$app_bundle/Contents/MacOS"
cp .build/release/session-engram "$app_bundle/Contents/MacOS/session-engram"

plutil -create xml1 "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleName -string "Session Engram" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Session Engram" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "dev.johney4415.session-engram" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "session-engram" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundlePackageType -string "APPL" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "0.1.0" "$app_bundle/Contents/Info.plist"
plutil -replace LSUIElement -bool true "$app_bundle/Contents/Info.plist"

printf 'Installed app: %s\n' "$app_bundle"
printf 'Next: open "%s" to put it in the menu bar.\n' "$app_bundle"
