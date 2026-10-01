#!/usr/bin/env bash
# make-sounds.sh: converts App/Sounds/*.wav to the CAF files the app bundles,
# 22.05 kHz mono IMA4, then removes the WAVs. macOS only (afconvert).
set -euo pipefail
cd "$(dirname "$0")/../App/Sounds"
for wav in *.wav; do
  afconvert -f caff -d ima4@22050 -c 1 "$wav" "${wav%.wav}.caf"
  rm "$wav"
done
ls -l *.caf
