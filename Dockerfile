# The Linux toolchain for AlarmCore: the package's logic, tests and format
# check run here, in the same image in CI and on the dev box. The app itself
# needs Xcode and builds on the macOS runner (.github/workflows/ci.yml).
FROM swift:6.4.2-resolute@sha256:119ff7d833ea622851b459513333bb4bda5ebb32b7acd05dd05077d5b0383129 AS toolchain

WORKDIR /src

# Prose rules (scripts/check-prose.sh) and workflow lint (make lint). Named
# stages, so Dependabot bumps them with the rest.
FROM jdkato/vale:v3.26.0@sha256:d4ebc402b255dacc759c468ed8c91bd5be82918bbb59583558539f3be80f1f01 AS vale
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint
