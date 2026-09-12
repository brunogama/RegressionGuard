set shell := ["/bin/bash", "-euo", "pipefail", "-c"]

# Flags CI builds with. Kept here so a local run fails for the same reasons.
strict := "-Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete"

# Show the available recipes.
default:
    @just --list

# Build the package and its tests.
build:
    swift build --build-tests {{strict}}

# Run the test suite.
test:
    swift test --parallel {{strict}}

# Run the tests with coverage and enforce the RegressionGuardKit floor.
coverage:
    swift test --enable-code-coverage --parallel {{strict}}
    ./scripts/coverage-gate.sh

# Format Swift sources in place.
format *files="Sources Tests Plugins":
    swift-format format --in-place --recursive {{files}}

# Run every prek hook over the whole tree, as the pull request job does.
lint:
    prek run --all-files

# Everything CI checks, in CI's order.
check: lint build coverage

# Run the guard against your own changes, as the self-check workflow does.
guard base="main":
    swift build -c release
    .build/release/regression-guard check --base "{{base}}" --head HEAD --format text

# Record an observation artifact from a guard report.
observe base="main":
    swift build -c release
    .build/release/regression-guard check --base "{{base}}" --head HEAD \
      --format text --report-file regression-guard-report.json || true
    .build/release/regression-guard-observer \
      --report-file regression-guard-report.json \
      --output-file regression-guard-observation.json

# Run the guard through the SwiftPM command plugin.
plugin:
    swift package regression-guard

# Drop build products and generated coverage evidence.
clean:
    rm -rf .build
    rm -f regression-guard-coverage.lcov regression-guard-coverage.json coverage-summary.txt
