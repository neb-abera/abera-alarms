#!/usr/bin/env bash
#
# test-app.sh: build the app for the simulator and run the UI tests, on the
# newest iPhone simulator the selected Xcode has, then print the app
# target's line coverage.
#
#   scripts/test-app.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# The newest iOS runtime, and the first iPhone on it.
device="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ios = sorted((k for k in devices if ".iOS-" in k),
             key=lambda k: [int(p) for p in k.rsplit(".iOS-", 1)[1].split("-")])
for runtime in reversed(ios):
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"]); break
')"
[ -n "$device" ] || { echo "error: no iPhone simulator available" >&2; exit 1; }
xcrun simctl list devices | grep "$device"

mkdir -p build
rm -rf build/AberaAlarms.xcresult
status=0
xcodebuild test \
  -project AberaAlarms.xcodeproj \
  -scheme AberaAlarms \
  -destination "id=$device" \
  -resultBundlePath build/AberaAlarms.xcresult \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  > build/xcodebuild.log 2>&1 || status=$?

grep -E '^(Test Case|Test Suite|\*\*)|error:|warning:' build/xcodebuild.log || true
if [ "$status" -ne 0 ]; then
  echo "error: xcodebuild exited $status. The last 80 lines of build/xcodebuild.log:" >&2
  tail -80 build/xcodebuild.log >&2
fi
xcrun xccov view --report --only-targets build/AberaAlarms.xcresult 2>/dev/null || true
exit "$status"
