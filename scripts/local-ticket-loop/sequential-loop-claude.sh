#!/usr/bin/env bash
# Runs loop-claude.sh across an explicit set of local tickets, computing
# dependency waves from each ticket's "## Blocked by" field (a wave is the
# set of tickets whose blockers are all satisfied once the previous wave
# finishes). Tickets within a wave still run one at a time, in the SAME
# checkout that loop-claude.sh already serializes via its campaign lock -
# this script does not parallelize execution. True concurrent execution
# would need one git worktree per ticket and risks real merge conflicts
# given how much the 12-series tickets share files (router.go, service.go,
# discovery.go, App.tsx); waves here are for visibility and correct
# ordering, not wall-clock speedup.
#
# Requires an explicit ticket-ID list - it never defaults to "every open
# ticket in .scratch/tickets", since that directory also holds unrelated
# older tickets (01-11) that are not part of the current work.

set -euo pipefail
umask 077

TOOL_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TOOL_DIR
ROOT_DIR="$(git -C "$TOOL_DIR" rev-parse --show-toplevel)"
readonly ROOT_DIR
readonly TICKET_DIR="${LOCAL_TICKET_DIR:-$ROOT_DIR/.scratch/tickets}"
readonly LOOP_BIN="$TOOL_DIR/loop-claude.sh"
readonly WATCH_BIN="$TOOL_DIR/watch-progress.sh"
readonly SEQUENTIAL_AUTO_WATCH="${SEQUENTIAL_AUTO_WATCH:-1}"

WATCH_PID=""

# loop-claude.sh's own auto-tail only covers the single ticket it is
# currently running. Across a whole multi-wave, multi-ticket campaign that
# goes stale the moment execution advances to the next ticket, so start the
# ticket-following watcher for the WHOLE campaign here instead, and make
# sure it is stopped on every exit path - success, a failed ticket, or
# Ctrl-C - not just the happy path at the bottom of the script.
stop_watch() {
	[[ -n "$WATCH_PID" ]] || return 0
	kill "$WATCH_PID" 2>/dev/null || true
	wait "$WATCH_PID" 2>/dev/null || true
	WATCH_PID=""
}
trap stop_watch EXIT

usage() {
	cat <<'EOF'
Usage: scripts/local-ticket-loop/sequential-loop-claude.sh <ticket-id> [ticket-id ...]

Computes dependency waves for the given tickets from their "## Blocked by"
fields, then runs loop-claude.sh for each ticket in wave order (one ticket
at a time; waves are for visibility, not concurrency). Stops immediately if
any ticket's loop-claude.sh run fails, so a broken run does not cascade into
tickets that depend on it.

Environment:
  SEQUENTIAL_AUTO_WATCH   1 (default) to auto-launch watch-progress.sh for
                          the whole campaign; 0 to disable

Example (resuming the 12-series campaign after 12o finished):
  scripts/local-ticket-loop/sequential-loop-claude.sh 12h 12j 12n 12k 12l 12p
EOF
}

fail() {
	printf 'sequential ticket loop: %s\n' "$*" >&2
	exit 1
}

case "${1:-}" in
--help | -h)
	usage
	exit 0
	;;
esac

(($# > 0)) || {
	usage >&2
	exit 2
}

[[ -x "$LOOP_BIN" ]] || fail "loop-claude.sh not found or not executable: $LOOP_BIN"
[[ -d "$TICKET_DIR" ]] || fail "ticket directory not found: $TICKET_DIR"

ticket_id() { basename "$1" .md; }

ticket_has_open_criteria() {
	grep -qE '^[-*] \[ \]' "$1"
}

# Prints each blocker ticket ID referenced in a ticket's "## Blocked by"
# section, one per line (e.g. "- #12i (...)" -> "12i").
blockers_of() {
	awk '/^## Blocked by/{flag=1;next}/^## /{flag=0}flag' "$1" \
		| grep -oE '#[0-9]+[a-z]?' | tr -d '#'
}

is_complete() {
	# Two separate `local` statements are required: `local id=X file=$id`
	# expands $id from the CALLER's scope before either local takes effect
	# (bash evaluates the whole local word list before declaring any of
	# it), so a single combined statement would silently read the wrong
	# ticket file whenever a caller-scope variable is also named "id".
	local id="$1"
	local file="$TICKET_DIR/$id.md"
	# A blocker ID with no ticket file is a typo or an unavailable
	# prerequisite; treating it as satisfied would schedule a dependent
	# ticket whose dependencies were never met.
	[[ -f "$file" ]] || return 1
	ticket_has_open_criteria "$file" && return 1 || return 0
}

in_array() {
	local needle="$1" x
	shift
	for x in "$@"; do
		[[ "$x" == "$needle" ]] && return 0
	done
	return 1
}

declare -a candidates=()
for arg in "$@"; do
	file="$TICKET_DIR/$arg.md"
	[[ -f "$file" ]] || fail "ticket not found: $file"
	if ! ticket_has_open_criteria "$file"; then
		printf 'sequential ticket loop: ticket %s already complete; skipping\n' "$arg" >&2
		continue
	fi
	candidates+=("$arg")
done
((${#candidates[@]} > 0)) || fail "every requested ticket is already complete"

# all_candidates never shrinks; remaining does, as tickets are assigned to
# waves. A blocker still in remaining is not ready yet. A blocker that is a
# candidate but no longer in remaining was assigned to an EARLIER wave, so
# by the time execution reaches this wave it will already be done - trust
# the wave ordering, don't re-read its (necessarily still-open) file during
# pure planning before anything has actually run. Only a blocker that was
# never a candidate at all (an external ticket this invocation isn't
# running) needs its on-disk completion checked right now.
declare -a all_candidates=("${candidates[@]}")
declare -a remaining=("${candidates[@]}")
declare -a waves=()

while ((${#remaining[@]} > 0)); do
	declare -a ready=()
	declare -a still_blocked=()
	for id in "${remaining[@]}"; do
		ready_flag=1
		while IFS= read -r blocker; do
			[[ -n "$blocker" && "$blocker" != "$id" ]] || continue
			if in_array "$blocker" "${remaining[@]}"; then
				ready_flag=0
				break
			fi
			if in_array "$blocker" "${all_candidates[@]}"; then
				continue
			fi
			if ! is_complete "$blocker"; then
				ready_flag=0
				break
			fi
		done < <(blockers_of "$TICKET_DIR/$id.md")
		if ((ready_flag == 1)); then
			ready+=("$id")
		else
			still_blocked+=("$id")
		fi
	done
	((${#ready[@]} > 0)) || fail "dependency cycle or unresolved external blocker among: ${still_blocked[*]}"
	waves+=("${ready[*]}")
	remaining=("${still_blocked[@]}")
done

printf 'sequential ticket loop: %d wave(s) computed:\n' "${#waves[@]}" >&2
wave_num=0
for wave in "${waves[@]}"; do
	wave_num=$((wave_num + 1))
	printf 'sequential ticket loop:   wave %d: %s\n' "$wave_num" "$wave" >&2
done

if [[ "$SEQUENTIAL_AUTO_WATCH" == "1" && -x "$WATCH_BIN" ]]; then
	"$WATCH_BIN" &
	WATCH_PID=$!
fi

wave_num=0
for wave in "${waves[@]}"; do
	wave_num=$((wave_num + 1))
	printf 'sequential ticket loop: === wave %d/%d: %s ===\n' "$wave_num" "${#waves[@]}" "$wave" >&2
	for id in $wave; do
		printf 'sequential ticket loop: --- starting %s ---\n' "$id" >&2
		"$LOOP_BIN" "$id" || fail "loop-claude.sh failed on ticket $id (wave $wave_num/${#waves[@]}); stopping, remaining waves not started"
		printf 'sequential ticket loop: --- finished %s ---\n' "$id" >&2
	done
	printf 'sequential ticket loop: === wave %d/%d complete ===\n' "$wave_num" "${#waves[@]}" >&2
done

printf 'sequential ticket loop: all waves complete\n' >&2
