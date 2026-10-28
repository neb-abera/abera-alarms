#!/usr/bin/env bash
#
# test-app.sh: build the app for the simulator and run the UI tests, on the
# newest iPhone simulator the selected Xcode has, then print the app
# target's line coverage.
#
#   scripts/test-app.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# The highest-numbered "iPhone N Pro" on the newest iOS that has one, among
# the simulators the selected Xcode can run, else the newest iPhone. The
# list goes to the log. The earlier pick read simctl. From
# 2026-10-26 it took an iPhone Duo on the Xcode 27 runner, and six list
# tests failed. On 2026-10-28 the same pick failed with "The iOS 27.1
# simulator runtime is not available". The last green run, on 2026-10-19,
# had used the iPhone 18 Pro.
device="$(xcodebuild -showdestinations -project AberaAlarms.xcodeproj -scheme AberaAlarms 2>/dev/null | python3 -c '
import re, sys
found = []
for line in sys.stdin:
    m = re.search(r"platform:iOS Simulator,.* id:([0-9A-F-]{36}), OS:([0-9.]+), name:(iPhone[^}]*?) \}", line)
    if m:
        found.append((tuple(int(p) for p in m.group(2).split(".")), m.group(3), m.group(1)))
for f in sorted(found):
    print(".".join(map(str, f[0])), f[1], f[2], file=sys.stderr)
pros = [(f[0], int(m.group(1)), f[2]) for f in found if (m := re.fullmatch(r"iPhone (\d+) Pro", f[1]))]
if pros:
    print(max(pros)[2])
elif found:
    print(max(found)[2])
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
