#!/bin/bash
# Times 30 sequential `git show` invocations against one batched `git cat-file`, the
# same measurement the capability research made, so this machine's subprocess cost can
# be compared against the 9.24 ms/spawn that its proposed budget was built on.
set -euo pipefail
repo="${1:-.}"
paths=$(/usr/bin/git -C "$repo" ls-files '*.swift' | head -30)
count=$(printf '%s\n' "$paths" | wc -l | tr -d ' ')

now() { python3 -c 'import time; print(time.monotonic_ns())'; }
report() { python3 -c "print(f'$1: {($3-$2)/1e6:.1f} ms total, {($3-$2)/1e6/$4:.2f} ms each')"; }

start=$(now)
for p in $paths; do /usr/bin/git -C "$repo" show "HEAD:$p" > /dev/null; done
report "$count x git show" "$start" "$(now)" "$count"

start=$(now)
printf 'HEAD:%s\n' $paths | /usr/bin/git -C "$repo" cat-file --batch > /dev/null
report "1 x git cat-file --batch" "$start" "$(now)" 1
