#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/boop-recognition.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -module-cache-path "$check_dir/module-cache" \
  -target "$(uname -m)-apple-macos15.0" \
  Boop/Capture/ScreenTextMatcher.swift Boop/Capture/ScreenSelectionLocator.swift \
  scripts/check-screen-recognition.swift -o "$check_dir/check-recognition"
"$check_dir/check-recognition" "$@"
