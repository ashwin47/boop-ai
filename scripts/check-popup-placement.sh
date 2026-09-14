#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/boop-placement.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -module-cache-path "$check_dir/module-cache" \
  -target "$(uname -m)-apple-macos15.0" \
  Boop/Capture/TextCapture.swift Boop/Capture/Synthetic.swift \
  Boop/Capture/ScreenSelectionLocator.swift Boop/Capture/ScreenTextMatcher.swift \
  Boop/UI/PopupPlacement.swift scripts/check-popup-placement.swift \
  -o "$check_dir/check-placement"
"$check_dir/check-placement"
