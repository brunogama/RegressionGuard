#!/bin/bash
# Runs the scenario set behind the parse performance budget and prints one row per
# (scenario, base-fetch strategy). Scenarios are real commits, picked by survey.sh
# for their Swift file counts, plus two deliberately large release-to-release diffs.
#
# Scenario labels carry the file count the harness itself reports, which counts a
# rename as two paths: `git diff --name-only` will say 501 where this says 504.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bench="$here/.build/release/parsebench"
guard="$(cd "$here/../../.." && pwd)"
syntax="$here/.build/checkouts/swift-syntax"

header=--header

run() {
  "$bench" --repo "$1" --base "$2" --head "$3" --label "$4" \
    --repeat "${5:-5}" --strategy "${6:-per-file,batched}" ${header:+--header yes}
  header=
}

run "$guard" 'edf6a4f^' edf6a4f 'guard/1-file'
run "$guard" 'f4b0336^' f4b0336 'guard/6-file'
run "$guard" '21699c1^' 21699c1 'guard/13-file'
run "$guard" 'b0780dc^' b0780dc 'guard/26-file'
run "$guard" 'a301c1a^' a301c1a 'guard/45-file'
run "$syntax" '8ea19b601^' 8ea19b601 'swift-syntax/50-file'
run "$syntax" '9e40b4022^' 9e40b4022 'swift-syntax/83-file'
# One repeat past this size. The per-file sweep is thousands of spawns and takes
# minutes, but it is run: the worst case is the row the budget is written about, and
# reading it only through the strategy already known to win would prove nothing.
run "$syntax" 602.0.0 603.0.0 'swift-syntax/243-file' 1 per-file
run "$syntax" 602.0.0 603.0.0 'swift-syntax/243-file' 3 batched
run "$syntax" 600.0.0 603.0.0 'swift-syntax/504-file' 1 per-file
run "$syntax" 600.0.0 603.0.0 'swift-syntax/504-file' 3 batched
