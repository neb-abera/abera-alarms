#!/usr/bin/env bash
#
# release.sh: the Release build that goes to TestFlight.
#
#   scripts/release.sh archive   archive build/AberaAlarms.xcarchive. Signed
#                                when ASC_KEY_P8 is set, unsigned otherwise
#                                (a pull request proves the Release build).
#   scripts/release.sh upload    export the signed archive and upload it to
#                                App Store Connect, which hands it to TestFlight.
#
# Signing and upload use an App Store Connect API key with the App Manager
# role, from the environment: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (the
# .p8 file's text). Xcode's cloud-managed signing makes the distribution
# certificate and profile, so no certificate lives in this repository.
#
# The version is the date, YYYY.M.D, as the repository's date scheme tags a
# deploy. The build number is BUILD_NUMBER, else the CI run number, else the
# Unix time.

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=9K44N8AGF7
ARCHIVE=build/AberaAlarms.xcarchive
VERSION="$(date -u +%Y.%-m.%-d)"
BUILD="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$(date -u +%s)}}"
mkdir -p build

key_args=()
cleanup() { [ -n "${KEY_FILE:-}" ] && rm -f "$KEY_FILE"; }
trap cleanup EXIT
if [ -n "${ASC_KEY_P8:-}" ]; then
  : "${ASC_KEY_ID:?ASC_KEY_ID is required with ASC_KEY_P8}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_P8}"
  KEY_FILE="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/asc-key.XXXXXX")"
  chmod 600 "$KEY_FILE"
  printf '%s\n' "$ASC_KEY_P8" > "$KEY_FILE"
  key_args=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_FILE"
    -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

case "${1:-}" in
  archive)
    rm -rf "$ARCHIVE"
    signing=(CODE_SIGNING_ALLOWED=NO)
    if [ ${#key_args[@]} -gt 0 ]; then
      signing=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)
    fi
    echo "Archiving version $VERSION, build $BUILD"
    xcodebuild archive \
      -project AberaAlarms.xcodeproj -scheme AberaAlarms -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
      MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
      ${key_args[@]+"${key_args[@]}"} "${signing[@]}" \
      | grep -E '(error|warning):|\*\* ARCHIVE' || true
    [ -d "$ARCHIVE/Products/Applications/AberaAlarms.app" ] \
      || { echo "error: no app in $ARCHIVE" >&2; exit 1; }
    ;;
  upload)
    [ ${#key_args[@]} -gt 0 ] || { echo "error: upload needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8" >&2; exit 1; }
    cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
      -exportPath build/export "${key_args[@]}"
    echo "Uploaded version $VERSION, build $BUILD. TestFlight has it once Apple finishes processing."
    ;;
  *)
    echo "usage: scripts/release.sh archive|upload" >&2
    exit 2
    ;;
esac
