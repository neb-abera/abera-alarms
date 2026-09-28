#!/usr/bin/env bash
#
# select-xcode.sh: switch the runner to the Xcode that .xcode-version names,
# and print the exact version and the SDKs it brings. A runner without it
# fails and lists what it has.

set -euo pipefail
cd "$(dirname "$0")/.."

want="$(tr -d '[:space:]' < .xcode-version)"
app=""
for candidate in /Applications/Xcode_"$want"*.app /Applications/Xcode-"$want"*.app; do
  [ -d "$candidate" ] && { app="$candidate"; break; }
done
if [ -z "$app" ]; then
  echo "error: no Xcode $want on this runner. It has:" >&2
  ls -d /Applications/Xcode*.app >&2
  exit 1
fi

sudo xcode-select -s "$app/Contents/Developer"
xcodebuild -version
xcodebuild -showsdks | grep -E 'iOS|Simulator' || true
