# The Linux toolchain for AlarmCore: the package's logic, tests and format
# check run here, in the same image in CI and on the dev box. The app itself
# needs Xcode and builds on the macOS runner (.github/workflows/ci.yml).
FROM swift:6.4.0-resolute@sha256:4601bf61dab9485a3e93087770b72d268737e945a5b000e2286b6cc48bb048b6 AS toolchain

WORKDIR /src

# Prose rules (scripts/check-prose.sh) and workflow lint (make lint). Named
# stages, so Dependabot bumps them with the rest.
FROM jdkato/vale:v3.24.0@sha256:f5a09410093936d4919d868120786da9789e2652ac321c66a895403eca020ae4 AS vale
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint
