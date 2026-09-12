#!/usr/bin/env bash
# Standard network-enabled validation. Does not use the offline host-library helper.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -En '^[[:space:]]*(@[^ ]+[[:space:]]+)?import[[:space:]]' Sources/SCMACore/*.swift; then
    printf '%s\n' 'SCMACore must not import external modules.' >&2
    exit 1
fi
swift package dump-package >/dev/null
swift build
swift test
python3 scripts/smoke-test.py --binary .build/debug/scma --plugins
