#!/usr/bin/env bash
# Shared process helpers for local ticket loop entrypoints.

run_with_timeout() {
	local seconds="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout --signal=TERM --kill-after=5 "${seconds}s" "$@"
	elif command -v gtimeout >/dev/null 2>&1; then
		gtimeout --signal=TERM --kill-after=5 "${seconds}s" "$@"
	else
		perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
	fi
}
