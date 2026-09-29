#!/usr/bin/env bash
#
# coverage.sh <floor>: AlarmCore's line coverage from the last
# `swift test --enable-code-coverage`, sources only (no tests, no
# dependencies). Fails below <floor> percent, and when there is no number.
# Runs inside the Swift image, from Packages/AlarmCore (make coverage).

set -euo pipefail
floor="${1:?usage: coverage.sh <floor>}"

profile="$(find -L .build -name default.profdata -path '*codecov*' | head -1)"
binary="$(find -L .build -maxdepth 3 \( -name 'AlarmCoreTests.so' -o -name 'AlarmCorePackageTests.xctest' \) | head -1)"
[ -n "$profile" ] && [ -n "$binary" ] || { echo "error: no coverage data. Run swift test --enable-code-coverage first." >&2; exit 1; }

report="$(llvm-cov report "$binary" -instr-profile "$profile" -ignore-filename-regex='(\.build|Tests)/')"
printf '%s\n' "$report"

percent="$(printf '%s\n' "$report" | awk '/^TOTAL/ { v = $10; sub(/%/, "", v); print v }')"
[ -n "$percent" ] || { echo "error: llvm-cov printed no TOTAL line" >&2; exit 1; }
echo "AlarmCore line coverage: $percent% (floor $floor%)"
awk -v p="$percent" -v f="$floor" 'BEGIN { exit (p + 0 < f + 0) }' \
  || { echo "error: line coverage $percent% is below the floor of $floor%" >&2; exit 1; }
