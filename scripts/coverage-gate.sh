#!/usr/bin/env bash
# Enforces the RegressionGuardKit line-coverage floor from `swift test
# --enable-code-coverage` output.
#
# SwiftPM emits one merged `<Package>PackageTests.xctest` bundle under the
# classic build system and per-target bundles under the Swift Build system, so
# every discovered bundle is handed to llvm-cov and the report is then filtered
# down to RegressionGuardKit sources.
set -euo pipefail
cd "$(dirname "$0")/.."

source_prefix="Sources/RegressionGuardKit/"
minimum_coverage=90
lcov_file="regression-guard-coverage.lcov"
summary_file="coverage-summary.txt"
json_file="regression-guard-coverage.json"

profdata=$(find .build -path '*/codecov/default.profdata' -print -quit)
if test -z "$profdata"; then
    printf 'no coverage profile under .build; run swift test --enable-code-coverage\n' >&2
    exit 1
fi

objects=()
while IFS= read -r bundle; do
    binary="$bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
    if test -f "$binary"; then
        objects+=("$binary")
    fi
done < <(find .build -name '*.xctest' -type d -print | sort)

if test "${#objects[@]}" -eq 0; then
    printf 'no test bundle executables under .build\n' >&2
    exit 1
fi

printf 'Coverage objects:\n' >&2
printf '  %s\n' "${objects[@]}" >&2

llvm_cov_arguments=("${objects[0]}")
for object in "${objects[@]:1}"; do
    llvm_cov_arguments+=(-object "$object")
done

xcrun llvm-cov export \
    "${llvm_cov_arguments[@]}" \
    -instr-profile "$profdata" \
    -format lcov \
    > "$lcov_file"

read -r percentage hit total < <(
    awk -F: -v prefix="$source_prefix" '
        /^SF:/ { included = (index($2, prefix) > 0); next }
        /^end_of_record$/ { included = 0 }
        included && /^LF:/ { total += $2 }
        included && /^LH:/ { hit += $2 }
        END {
            if (total == 0) exit 1
            printf "%.2f %d %d\n", 100 * hit / total, hit, total
        }' "$lcov_file"
) || {
    printf 'no %s lines found in %s\n' "$source_prefix" "$lcov_file" >&2
    exit 1
}

printf 'RegressionGuardKit line coverage: %s%% (%s/%s)\n' \
    "$percentage" "$hit" "$total" | tee "$summary_file"
printf '{"lineCoverage": %s, "coveredLines": %s, "totalLines": %s}\n' \
    "$percentage" "$hit" "$total" > "$json_file"

if test -n "${GITHUB_STEP_SUMMARY:-}"; then
    cat "$summary_file" >> "$GITHUB_STEP_SUMMARY"
fi

awk -v coverage="$percentage" -v minimum="$minimum_coverage" \
    'BEGIN { exit coverage < minimum }'
