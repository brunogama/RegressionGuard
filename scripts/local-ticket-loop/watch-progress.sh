#!/usr/bin/env bash
# Tails whichever ticket's progress.log was most recently written to, and
# automatically switches when a newer one appears - so one long-running
# `watch-progress.sh` stays useful across an entire sequential-loop-claude.sh
# campaign instead of going stale the moment the loop moves to the next
# ticket. Runs until interrupted (Ctrl-C).

set -euo pipefail

TOOL_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TOOL_DIR
ROOT_DIR="$(git -C "$TOOL_DIR" rev-parse --show-toplevel)"
readonly ROOT_DIR
GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --absolute-git-dir)"
readonly GIT_DIR
readonly RUNS_DIR="$GIT_DIR/local-ticket-loop/runs"
readonly POLL_SECONDS="${WATCH_POLL_SECONDS:-2}"

usage() {
	cat <<'EOF'
Usage: scripts/local-ticket-loop/watch-progress.sh

Tails the most recently updated runs/ticket-<id>/progress.log under
.git/local-ticket-loop, switching automatically whenever a newer one
appears (e.g. sequential-loop-claude.sh advancing to the next ticket).
Runs until interrupted with Ctrl-C.

Environment:
  WATCH_POLL_SECONDS   How often to check for a newer progress.log (default: 2)
EOF
}

case "${1:-}" in
--help | -h)
	usage
	exit 0
	;;
esac

fail() {
	printf 'watch-progress: %s\n' "$*" >&2
	exit 1
}

# A fresh campaign launches this watcher before loop-claude.sh creates the
# runs directory; wait briefly for it instead of exiting before the first run.
for _ in $(seq 1 60); do
	[[ -d "$RUNS_DIR" ]] && break
	sleep 1
done
[[ -d "$RUNS_DIR" ]] || fail "no run directory yet (nothing has run): $RUNS_DIR"

TAIL_PID=""
CURRENT_LOG=""

cleanup() {
	[[ -n "$TAIL_PID" ]] || return 0
	kill "$TAIL_PID" 2>/dev/null || true
	wait "$TAIL_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

latest_progress_log() {
	find "$RUNS_DIR" -maxdepth 2 -name progress.log -exec stat -f '%m %N' {} \; 2>/dev/null \
		| sort -rn | head -n 1 | cut -d' ' -f2-
}

# Reap a dead tail process so switch_to can respawn it on the next poll.
# Without this, once tail exits (e.g. its log was removed) the unchanged path
# passes switch_to's early-return guard and the watcher stays silent forever.
reap_tail() {
	[[ -n "$TAIL_PID" ]] || return 0
	if kill -0 "$TAIL_PID" 2>/dev/null; then
		return 0
	fi
	wait "$TAIL_PID" 2>/dev/null || true
	TAIL_PID=""
	CURRENT_LOG=""
}

switch_to() {
	local new_log="$1"
	[[ "$new_log" != "$CURRENT_LOG" ]] || return 0
	if [[ -n "$TAIL_PID" ]]; then
		kill "$TAIL_PID" 2>/dev/null || true
		wait "$TAIL_PID" 2>/dev/null || true
		TAIL_PID=""
	fi
	CURRENT_LOG="$new_log"
	printf 'watch-progress: now following %s\n' "$CURRENT_LOG" >&2
	tail -n 20 -f "$CURRENT_LOG" &
	TAIL_PID=$!
}

printf 'watch-progress: watching %s for the most recently updated progress.log\n' "$RUNS_DIR" >&2
while true; do
	reap_tail
	latest="$(latest_progress_log || true)"
	[[ -z "$latest" ]] || switch_to "$latest"
	sleep "$POLL_SECONDS"
done
