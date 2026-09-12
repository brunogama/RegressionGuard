#!/bin/bash
# Lists each commit in a repository by how many Swift files its diff touches, so the
# scenarios are picked from real history rather than assembled to flatter the result.
#
# Counts the same way parsebench does - `--name-status --no-renames`, so a rename is
# the two paths it really costs - and skips the root commit, which has no parent.
set -euo pipefail
repo="$1"
limit="${2:-60}"
for sha in $(/usr/bin/git -C "$repo" log --format=%h -"$limit"); do
  /usr/bin/git -C "$repo" rev-parse --verify --quiet "$sha^" > /dev/null || continue
  count=$(
    /usr/bin/git -C "$repo" diff --name-status --no-renames "$sha^..$sha" -- '*.swift' | wc -l
  )
  printf '%s\t%s\t%s\n' "$(echo "$count" | tr -d ' ')" "$sha" \
    "$(/usr/bin/git -C "$repo" log -1 --format=%s "$sha")"
done | sort -rn
