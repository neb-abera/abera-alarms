# The Linux toolchain for AlarmCore: the package's logic, tests and format
# check run here, in the same image in CI and on the dev box. The app itself
# needs Xcode and builds on the macOS runner (.github/workflows/ci.yml).
FROM swift:6.4.2-resolute@sha256:0384f00cf80f81064a907c249a0ad56a1648906f65075a95b1827e88de666e21 AS toolchain

WORKDIR /src

# Prose rules (scripts/check-prose.sh) and workflow lint (make lint). Named
# stages, so Dependabot bumps them with the rest.
FROM jdkato/vale:v3.28.1@sha256:42b74f7f3ea7dd60554181037a8899a190516b9d48b67d157b09e5df791f9115 AS vale
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint
