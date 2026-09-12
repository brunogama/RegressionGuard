#!/usr/bin/env bash
# Enforces the RegressionGuardKit line-coverage floor from `swift test
# --enable-code-coverage` output.
#
# SwiftPM emits one merged `<Package>PackageTests.xctest` bundle under the
# classic build system and per-target bundles under the Swift Build system. Both
# trees can be present at once, each holding its own profile, and only one of
# them belongs to the run that just happened. A profile has to be paired with
# the bundles from its own tree - read against another tree's binaries it either
# fails to load or reports code that ran as uncovered - so each tree is tried,
# newest profile first, and the first pairing that loads wins. The report is then
# filtered down to RegressionGuardKit sources.
set -euo pipefail
cd "$(dirname "$0")/.."

source_prefix="Sources/RegressionGuardKit/"
minimum_coverage=90
lcov_file="regression-guard-coverage.lcov"
summary_file="coverage-summary.txt"
json_file="regression-guard-coverage.json"

# Newest profile first, so a fresh run wins over a stale tree left behind.
profiles=$(
    find .build -path '*/codecov/default.profdata' -exec stat -f '%m %N' {} + |
        sort -rn | cut -d' ' -f2-
)
if test -z "$profiles"; then
    printf 'no coverage profile under .build; run swift test --enable-code-coverage\n' >&2
    exit 1
fi

exported=""
while IFS= read -r profdata; do
    test -n "$profdata" || continue
    # `<tree>/codecov/default.profdata` -> `<tree>`, the bundles this profile describes.
    profile_tree=$(dirname "$(dirname "$profdata")")

    objects=()
    while IFS= read -r bundle; do
        binary="$bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
        if test -f "$binary"; then
            objects+=("$binary")
        fi
    done < <(find "$profile_tree" -name '*.xctest' -type d -print | sort)

    if test "${#objects[@]}" -eq 0; then
        continue
    fi

    llvm_cov_arguments=("${objects[0]}")
    for object in "${objects[@]:1}"; do
        llvm_cov_arguments+=(-object "$object")
    done

    if xcrun llvm-cov export \
        "${llvm_cov_arguments[@]}" \
        -instr-profile "$profdata" \
        -format lcov \
        > "$lcov_file" 2>/dev/null; then
        exported="$profdata"
        printf 'Coverage profile:\n  %s\n' "$profdata" >&2
        printf 'Coverage objects:\n' >&2
        printf '  %s\n' "${objects[@]}" >&2
        break
    fi
done <<EOF
$profiles
EOF

if test -z "$exported"; then
    printf 'no profile under .build could be read against its own test bundles\n' >&2
    exit 1
fi

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
