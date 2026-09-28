# The Linux gates for AlarmCore, in the pinned Swift image. The app's build,
# unit and UI tests need Xcode: see README.md, "Build the app".
IMAGE := abera-alarms-$(notdir $(CURDIR)):toolchain
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
RUN := docker run --rm --user $(HOST_UID):$(HOST_GID) -e HOME=/tmp -v $(CURDIR):/src -w /src/Packages/AlarmCore $(IMAGE)

.PHONY: image test coverage format lint gates check prose clean

# The lowest line coverage AlarmCore may report. Raise it when the number clears it.
COVERAGE_FLOOR := 95

image:
	docker build --target toolchain -t $(IMAGE) .

test: image
	$(RUN) swift test --enable-code-coverage

coverage: test
	$(RUN) ../../scripts/coverage.sh $(COVERAGE_FLOOR)

format: image
	$(RUN) swift format --in-place --recursive Sources Tests ../../App ../../AppUITests

LINT_IMAGE = $(shell sed -n 's|^FROM \(rhysd/actionlint:[^ ]*\) AS actionlint$$|\1|p' Dockerfile)

lint: image
	$(RUN) swift format lint --strict --recursive Sources Tests ../../App ../../AppUITests
	@test -n "$(LINT_IMAGE)" || { echo "error: no 'FROM rhysd/actionlint:... AS actionlint' stage in the Dockerfile" >&2; exit 1; }
	docker run --rm --user $(HOST_UID):$(HOST_GID) -v $(CURDIR):/repo:ro -w /repo --entrypoint actionlint $(LINT_IMAGE) -color
	docker run --rm --user $(HOST_UID):$(HOST_GID) -v $(CURDIR):/repo:ro -w /repo --entrypoint shellcheck $(LINT_IMAGE) scripts/*.sh

prose:
	scripts/check-prose.sh

gates:
	scripts/check-version.sh --self-test
	scripts/check-version.sh
	scripts/check-concurrency.sh --self-test
	scripts/check-concurrency.sh
	scripts/check-required-contexts.sh --self-test
	scripts/check-required-contexts.sh
	scripts/check-prose.sh --self-test
	scripts/check-prose.sh

check: lint coverage gates

clean:
	docker image rm -f $(IMAGE)
