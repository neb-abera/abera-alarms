#!/usr/bin/env bash
#
# xcodegen.sh: regenerate AberaAlarms.xcodeproj from project.yml with the
# XcodeGen release pinned in tools/xcodegen.env, checked against its SHA-256.
#
#   scripts/xcodegen.sh           regenerate the project
#   scripts/xcodegen.sh --check   fail when the committed project differs
#
# macOS only: XcodeGen ships a macOS binary.

set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
. tools/xcodegen.env

cache="${XDG_CACHE_HOME:-$HOME/.cache}/abera-alarms/xcodegen-$XCODEGEN_VERSION"
bin="$cache/xcodegen/bin/xcodegen"
if [ ! -x "$bin" ]; then
  mkdir -p "$cache"
  zip="$cache/xcodegen.zip"
  curl -fsSL -o "$zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
  echo "$XCODEGEN_SHA256  $zip" | shasum -a 256 -c - >/dev/null \
    || { echo "error: xcodegen.zip does not match XCODEGEN_SHA256" >&2; rm -f "$zip"; exit 1; }
  unzip -q -o "$zip" -d "$cache"
fi

"$bin" generate --quiet

# XcodeGen writes the Info.plist and entitlement files too. On 2026-11-15
# App/Info.plist held LSApplicationQueriesSchemes that project.yml lacked, so
# every regeneration dropped it, and this check looked at the project alone.
generated=(AberaAlarms.xcodeproj ':(glob)**/Info.plist' ':(glob)**/*.entitlements')
if [ "${1:-}" = "--check" ]; then
  if ! git diff --quiet -- "${generated[@]}" || [ -n "$(git status --porcelain -- "${generated[@]}")" ]; then
    git status --short -- "${generated[@]}" >&2
    echo "error: the generated project or plists differ from project.yml. Run scripts/xcodegen.sh and commit them." >&2
    exit 1
  fi
fi
