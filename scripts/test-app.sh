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

# Boot first and wait, so the first test does not pay the cold start
# (51 s to launch the app on the xcode-27 runner) inside its two minutes.
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b

mkdir -p build
rm -rf build/AberaAlarms.xcresult
# Streamed, so a hung test shows where it hung. Each test gets two minutes.
set +e +o pipefail
xcodebuild test \
  -project AberaAlarms.xcodeproj \
  -scheme AberaAlarms \
  -destination "id=$device" \
  -resultBundlePath build/AberaAlarms.xcresult \
  -derivedDataPath build/DerivedData \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee build/xcodebuild.log \
  | grep --line-buffered -E '^(Test Case|Test Suite|\*\*)|error:|warning:|t = .*(Launch|Wait|Tap|Type|Find)'
status="${PIPESTATUS[0]}"
set -e -o pipefail

if [ "$status" -ne 0 ]; then
  echo "error: xcodebuild exited $status. The last 80 lines of build/xcodebuild.log:" >&2
  tail -80 build/xcodebuild.log >&2
fi
xcrun xccov view --report --only-targets build/AberaAlarms.xcresult 2>/dev/null || true
exit "$status"
