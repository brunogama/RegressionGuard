set shell := ["/bin/bash", "-euo", "pipefail", "-c"]

# Flags CI builds the root package with. The CLI package carries the same strictness in its own
# manifest instead, because -Xswiftc would also reach its dependencies.
strict := "-Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete"
cli := "--package-path RegressionGuardCLI"

# Show the available recipes.
default:
    @just --list

# Build both packages and their tests.
build:
    swift build --build-tests {{strict}}
    swift build {{cli}} --build-tests

# Run both test suites. `pipefail` is set above, so a failure still fails the recipe.
test:
    swift test --parallel {{strict}} | xcbeautify -q
    swift test {{cli}} --parallel | xcbeautify -q

# Run the tests with coverage and enforce the RegressionGuardKit floor.
coverage:
    swift test --enable-code-coverage --parallel {{strict}} | xcbeautify -q
    ./scripts/coverage-gate.sh

# Format Swift sources in place.
format *files="Sources Tests RegressionGuardCLI":
    swift-format format --in-place --recursive {{files}}

# Run every prek hook over the whole tree, as the pull request job does.
lint:
    prek run --all-files

# Everything CI checks, in CI's order.
check: lint build coverage

# Run the guard against your own changes, as the self-check workflow does.
guard base="main":
    swift build {{cli}} -c release
    RegressionGuardCLI/.build/release/regression-guard check --base "{{base}}" --head HEAD --format text

# Record an observation artifact from a guard report.
observe base="main":
    swift build {{cli}} -c release
    RegressionGuardCLI/.build/release/regression-guard check --base "{{base}}" --head HEAD \
      --format text --report-file regression-guard-report.json || true
    RegressionGuardCLI/.build/release/regression-guard-observer \
      --report-file regression-guard-report.json \
      --output-file regression-guard-observation.json

# Run the guard through the SwiftPM command plugin.
plugin:
    swift package {{cli}} regression-guard

# Build the universal CLI artifact bundle and print the checksum `Package.swift` needs.
artifactbundle version:
    python3 scripts/build-artifactbundle.py --version "{{version}}"

# Build and test the CLI against its vendored dependencies, as a machine with no network would.
offline:
    REGRESSIONGUARD_OFFLINE=1 swift build {{cli}} --build-tests
    REGRESSIONGUARD_OFFLINE=1 swift test {{cli}} --parallel | xcbeautify -q

# Drop build products and generated coverage evidence.
clean:
    rm -rf .build
    rm -f regression-guard-coverage.lcov regression-guard-coverage.json coverage-summary.txt
