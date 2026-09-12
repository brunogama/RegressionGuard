#!/usr/bin/env bash
# Run local Markdown implementation tickets through Claude Code, one at a time.
# Template-forked from scripts/local-ticket-loop/loop.sh. Replaces Pi's
# `--mode rpc` transport with `claude -p` (non-interactive print mode) and
# inlines the multi-stage skill gates as plain prompt instructions, so the
# loop no longer depends on pi-rpc-stream.mjs or any project-local skill
# registration. Shares the same campaign lock and run-state directory as
# loop.sh so the two loops cannot run against the same checkout at once.

set -euo pipefail
umask 077

TOOL_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TOOL_DIR
# shellcheck source=shared/process.sh
. "$TOOL_DIR/shared/process.sh"
ROOT_DIR="$(git -C "$TOOL_DIR" rev-parse --show-toplevel)"
readonly ROOT_DIR
readonly TICKET_DIR="${LOCAL_TICKET_DIR:-$ROOT_DIR/.scratch/deep-research-package/issues}"
readonly CLAUDE_BIN="${CLAUDE_BIN:-claude}"
readonly JQ_BIN="${JQ_BIN:-jq}"
readonly VERIFY_COMMAND="${RALPH_VERIFY_COMMAND:-swift build --build-tests && swift test}"
readonly COMMAND_TIMEOUT_SECONDS="${RALPH_COMMAND_TIMEOUT_SECONDS:-900}"
readonly CLAUDE_TIMEOUT_SECONDS="${RALPH_CLAUDE_TIMEOUT_SECONDS:-3600}"
readonly CLAUDE_MODEL="${CLAUDE_MODEL:-}"
readonly CLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE:-bypassPermissions}"
readonly CLAUDE_OUTPUT_FORMAT="${CLAUDE_OUTPUT_FORMAT:-stream-json}"
readonly CLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-}"
readonly CLAUDE_USE_DANGEROUS_SKIP="${CLAUDE_USE_DANGEROUS_SKIP:-1}"
readonly CLAUDE_APPEND_SYSTEM_PROMPT_FILE="${CLAUDE_APPEND_SYSTEM_PROMPT_FILE:-$TOOL_DIR/sr_opus_5_system_prompt.md}"
readonly AGENTMEMORY_PROJECT="${AGENTMEMORY_PROJECT:-$(basename "$ROOT_DIR")}"
readonly EXPECTED_BRANCH="${RALPH_EXPECTED_BRANCH:-}"
readonly RUN_OKF="${CLAUDE_RUN_OKF:-0}"
readonly START_AT_TICKET="${START_AT_TICKET:-}"
readonly STOP_AFTER_TICKET="${STOP_AFTER_TICKET:-}"
GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --absolute-git-dir)"
readonly GIT_DIR
readonly STATE_DIR="$GIT_DIR/local-ticket-loop"
readonly LOCK_DIR="$GIT_DIR/local-ticket-loop.lock"

# Paths the agent may never touch. The loop owns these; a diff containing any
# of them means the agent edited its own harness or its own tracking data.
readonly DENY_PATH_PATTERNS="${RALPH_DENY_PATH_PATTERNS:-^\.git/|^\.github/|^\.scratch/deep-research-package/issues/|^scripts/local-ticket-loop/}"

usage() {
	cat <<'EOF'
Usage: scripts/local-ticket-loop/loop-claude.sh [--list] [ticket-id ...]

Runs local Markdown tickets sequentially through Claude Code (`claude -p`
non-interactive print mode). With no ticket IDs, all unfinished files in
.scratch/deep-research-package/issues are considered in filename order.

Environment:
  LOCAL_TICKET_DIR                 Ticket directory
                                   (default: .scratch/deep-research-package/issues)
  START_AT_TICKET                  First ticket ID, inclusive
  STOP_AFTER_TICKET                Last ticket ID, inclusive
  CLAUDE_BIN                       Claude CLI binary (default: claude)
  CLAUDE_MODEL                     Optional Claude model id (e.g. claude-sonnet-4-5)
  CLAUDE_PERMISSION_MODE           Permission mode for non-interactive use
                                   (default: bypassPermissions)
  CLAUDE_OUTPUT_FORMAT             Output format: "stream-json" (default; live
                                   progress in runs/ticket-<id>/progress.log,
                                   resembling interactive Claude Code output)
                                   or "json" (single result, no live output)
  CLAUDE_ALLOWED_TOOLS             If set, comma-list passed via --allowedTools
  CLAUDE_USE_DANGEROUS_SKIP        1 to also pass --dangerously-skip-permissions
                                   (default: 1). Required so `bypassPermissions`
                                   works in headless `--print` mode.
  CLAUDE_APPEND_SYSTEM_PROMPT_FILE Path appended via --append-system-prompt-file
                                   (default: sr_opus_5_system_prompt.md next to
                                   this script, if it exists). Set empty to
                                   disable.
  AGENTMEMORY_PROJECT              agentmemory project scope for memory_recall/
                                   memory_save calls in ticket prompt (default:
                                   repo dir name)
  RALPH_CLAUDE_TIMEOUT_SECONDS     Per-ticket Claude timeout (default: 3600)
  RALPH_EXPECTED_BRANCH            If set, the checkout must be on this branch
  CLAUDE_RUN_OKF                   1 to append the /okf bundle stage (default: 0)
  RALPH_VERIFY_COMMAND             Verification command
                                   (default: swift build --build-tests && swift test)
  RALPH_COMMAND_TIMEOUT_SECONDS    Verification timeout (default: 900)

Notes:
  * For non-interactive runs, your `claude` installation must accept
    `--dangerously-skip-permissions`. Enable it once with
    `claude config set --global allowDangerouslySkipPermissions true`
    (or run an interactive `claude` and accept the prompt) before invoking
    this loop unattended.
  * This loop shares the campaign lock with loop.sh, so the two loops
    cannot run against the same checkout at the same time.

Examples:
  scripts/local-ticket-loop/loop-claude.sh --list
  scripts/local-ticket-loop/loop-claude.sh 01-fidelity-layer
  START_AT_TICKET=02-walking-skeleton-run STOP_AFTER_TICKET=05-cited-answer \
    scripts/local-ticket-loop/loop-claude.sh
  CLAUDE_MODEL=claude-sonnet-5 scripts/local-ticket-loop/loop-claude.sh 14-cache
EOF
}

PROGRESS_TAIL_PID=""

# Stops the background `tail -f progress.log` started for the current
# invocation, if any. Called from fail() and release_lock() (not just the
# happy path in run_ticket) so a tail process is never left running past
# the claude -p call it belongs to, on any exit path including Ctrl-C.
stop_progress_tail() {
	[[ -n "$PROGRESS_TAIL_PID" ]] || return 0
	kill "$PROGRESS_TAIL_PID" 2>/dev/null || true
	wait "$PROGRESS_TAIL_PID" 2>/dev/null || true
	PROGRESS_TAIL_PID=""
}

fail() {
	stop_progress_tail
	printf 'claude ticket loop: %s\n' "$*" >&2
	exit 1
}

step() {
	printf 'claude ticket loop: [%s] %s\n' "${CURRENT_TICKET:-*}" "$*" >&2
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

# Reads `claude -p --output-format stream-json --verbose` NDJSON events on
# stdin and prints a line-by-line transcript resembling interactive Claude
# Code output (assistant text, tool calls, tool results). Best-effort: never
# lets a malformed event line kill the underlying claude -p process, since
# this only feeds a human-readable side log, not the parsed completion report.
format_stream_json() {
	# shellcheck disable=SC2016 # jq variables belong to jq, not the shell.
	"$JQ_BIN" -r '
		def clip($n): if (length > $n) then (.[0:$n] + "…") else . end;
		if .type == "assistant" then
			(.message.content[]? |
				if .type == "text" then .text
				elif .type == "tool_use" then
					"⏺ " + .name + "(" + ((.input // {} | tojson) | clip(160)) + ")"
				else empty end)
		elif .type == "user" then
			(.message.content[]? | select(.type == "tool_result") |
				"  ⎿ " + (
					(if (.content | type) == "array"
						then ([.content[]? | select(.type == "text") | .text] | join(" "))
						else (.content // "" | tostring) end)
					| clip(200)
				))
		elif .type == "system" and .subtype == "init" then
			"[session started] model=" + (.model // "?")
		elif .type == "result" then
			"\n[claude -p finished] " + (.subtype // "unknown")
				+ (if .is_error then " (error)" else "" end)
		else empty end
	' 2>/dev/null || true
}

# Prints why `claude -p` failed. The stream's final result event carries the
# authoritative message; stderr is only a fallback, because startup noise there
# is easily mistaken for the cause.
report_claude_failure() {
	local id="$1" raw_json="$2" stderr_log="$3" result_json message
	result_json="$(tail -n 1 "$raw_json" 2>/dev/null || true)"
	if printf '%s' "$result_json" | "$JQ_BIN" -e '.type == "result"' >/dev/null 2>&1; then
		message="$(printf '%s' "$result_json" | "$JQ_BIN" -r '.result // .subtype // "unknown"')"
		printf 'claude ticket loop: ticket %s ended after %s turn(s): %s\n' \
			"$id" \
			"$(printf '%s' "$result_json" | "$JQ_BIN" -r '.num_turns // "?"')" \
			"$message" >&2
		case "$message" in
		*"usage limit"* | *"session limit"* | *"rate limit"*)
			printf 'claude ticket loop: this is a Claude usage limit, not a repository failure; the ticket worktree is retained so the run can be resumed after the limit resets\n' >&2
			;;
		esac
		return
	fi
	printf 'claude ticket loop: no result event for ticket %s; tail of stderr:\n' "$id" >&2
	tail -n 80 "$stderr_log" >&2 || true
}

release_lock() {
	stop_progress_tail
	rm -f "$LOCK_DIR/owner" 2>/dev/null || true
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

process_start_time() {
	# Fixed locale and timezone: ps lstart output is locale- and
	# timezone-formatted, so a contender with different settings would fail
	# the equality check and could remove a live lock.
	LC_ALL=C TZ=UTC ps -p "$1" -o lstart= 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/ $//'
}

acquire_lock() {
	local attempt owner
	for attempt in 1 2 3; do
		if mkdir "$LOCK_DIR" 2>/dev/null; then
			# Publish ownership immediately. Publication uses create-new so a
			# concurrent claimant that somehow entered the directory cannot be
			# overwritten; failure here means we lost the race, so back off.
			if (
				set -o noclobber
				printf '%s\n' "$$" >"$LOCK_DIR/owner"
			) 2>/dev/null; then
				trap release_lock EXIT
				return 0
			fi
			rmdir "$LOCK_DIR" 2>/dev/null || true
		else
			owner="$(cat "$LOCK_DIR/owner" 2>/dev/null || true)"
			if [[ "$owner" =~ ^[1-9][0-9]*$ ]] && kill -0 "$owner" 2>/dev/null; then
				fail "another local ticket loop owns this checkout (pid $owner)"
			fi
			# The owner file is absent (a paused contender between mkdir and
			# publication) or its pid is gone (a stale lock). Wait briefly for
			# publication, then remove the stale claim and retry atomically.
			sleep 1
			owner="$(cat "$LOCK_DIR/owner" 2>/dev/null || true)"
			if [[ "$owner" =~ ^[1-9][0-9]*$ ]] && kill -0 "$owner" 2>/dev/null; then
				fail "another local ticket loop owns this checkout (pid $owner)"
			fi
			rm -rf "$LOCK_DIR"
		fi
	done
	fail "could not acquire campaign lock after $attempt attempts"
}

# Working-tree changes that belong to the ticket. The agent harness writes a
# per-run record under .agents/evidence/ for the loop's own `claude -p` call;
# that file is not ticket work, and counting it would fail the post-verification
# clean check on every ticket.
worktree_dirt() {
	git status --porcelain | grep -vE '^\?\? \.agents/evidence/' || true
}

ticket_id() {
	basename "$1" .md
}

ticket_has_open_criteria() {
	grep -qE '^[[:space:]]*[-*] \[ \]' "$1"
}

ticket_criteria_count() {
	grep -cE '^[[:space:]]*[-*] \[[ xX]\]' "$1" || true
}

list_tickets() {
	local file id total open status
	for file in "$TICKET_DIR"/*.md; do
		[[ -e "$file" ]] || continue
		id="$(ticket_id "$file")"
		total="$(ticket_criteria_count "$file")"
		open="$(grep -cE '^[[:space:]]*[-*] \[ \]' "$file" || true)"
		status="complete"
		((open > 0)) && status="open"
		printf '%s\t%s\t%s/%s open\n' "$id" "$status" "$open" "$total"
	done
}

resolve_ticket_file() {
	local id="$1"
	local file="$TICKET_DIR/$id.md"
	[[ -f "$file" ]] || fail "ticket not found: $file"
	printf '%s\n' "$file"
}

select_tickets() {
	local file id started=1
	[[ -z "$START_AT_TICKET" ]] || started=0
	for file in "$TICKET_DIR"/*.md; do
		[[ -e "$file" ]] || continue
		id="$(ticket_id "$file")"
		if ((started == 0)) && [[ "$id" == "$START_AT_TICKET" ]]; then
			started=1
		fi
		((started == 1)) || continue
		printf '%s\n' "$file"
		if [[ -n "$STOP_AFTER_TICKET" && "$id" == "$STOP_AFTER_TICKET" ]]; then
			return
		fi
	done
	((started == 1)) || fail "START_AT_TICKET not found: $START_AT_TICKET"
	[[ -z "$STOP_AFTER_TICKET" ]] || fail "STOP_AFTER_TICKET not found after start: $STOP_AFTER_TICKET"
}

extract_completion_report() {
	local raw_json="$1" report_file="$2" text_file="$3"
	local result_json

	if [[ "$CLAUDE_OUTPUT_FORMAT" == "stream-json" ]]; then
		# raw_json holds one NDJSON event per line; the final line is the
		# same result object plain "json" mode returns as its whole output.
		result_json="$(tail -n 1 "$raw_json" 2>/dev/null || true)"
		if ! printf '%s' "$result_json" | "$JQ_BIN" -e '.type == "result"' >/dev/null 2>&1; then
			fail "claude -p stream did not end with a result event; inspect $raw_json"
		fi
	else
		result_json="$(cat "$raw_json" 2>/dev/null || true)"
	fi

	# Surface Claude Code error results explicitly so a usage-limit or
	# transport failure does not look like "agent did nothing".
	local is_error
	is_error="$(printf '%s' "$result_json" | "$JQ_BIN" -r '.is_error // false' 2>/dev/null || echo true)"
	if [[ "$is_error" == "true" ]]; then
		fail "claude -p returned an error result; inspect $raw_json"
	fi

	printf '%s' "$result_json" | "$JQ_BIN" -r '.result // empty' >"$text_file"
	if [[ ! -s "$text_file" ]]; then
		fail "claude -p returned no result field; inspect $raw_json"
	fi

	local count
	grep -E '^RALPH_COMPLETION_REPORT=' "$text_file" >"$report_file" || true
	count="$(wc -l <"$report_file" | tr -d '[:space:]')"
	[[ "$count" == "1" ]] || fail "expected one completion report, found $count"
	sed 's/^RALPH_COMPLETION_REPORT=//' "$report_file"
}

validate_completion_report() {
	local report="$1" baseline="$2" ticket="$3" result head_now
	printf '%s' "$report" | "$JQ_BIN" -e '
		type == "object" and .status == "complete"
		and .implementation.status == "complete"
		and .verification.status == "complete"
		and .code_review.status == "complete"
		and (.commit | type == "string" and test("^[0-9a-f]{40}$"))
	' >/dev/null || fail "ticket $ticket returned an incomplete or malformed report"
	result="$(printf '%s' "$report" | "$JQ_BIN" -r '.commit')"
	git cat-file -e "${result}^{commit}" 2>/dev/null || fail "ticket $ticket reported an unavailable commit"
	head_now="$(git rev-parse HEAD)"

	if git merge-base --is-ancestor "$result" "$baseline" 2>/dev/null; then
		# The agent found the ticket already fully implemented by a commit
		# at or before this run's baseline and made no new commit. That is
		# only a legitimate "nothing to do" outcome if the worktree truly
		# did not move; otherwise something changed without being reported.
		[[ "$head_now" == "$baseline" ]] || fail "ticket $ticket reported a pre-existing commit but HEAD moved"
		step "ticket $ticket already implemented at $result (no new commit required this run)"
		return
	fi

	[[ "$result" != "$baseline" ]] || fail "ticket $ticket produced no new commit"
	git merge-base --is-ancestor "$baseline" "$result" || fail "ticket $ticket result does not descend from its baseline"

	# The prompt's stage-gate contract requires the code-review fix and the
	# OKF bundle update to land as their own commits AFTER the implementation
	# commit, so HEAD is expected to be a descendant of $result, not equal to
	# it. The expected range is bounded to exactly those stages: the
	# implementation commit plus at most one code-review fix commit and one
	# OKF bundle commit. Anything longer means unreported work landed on the
	# branch and the ticket cannot be verified from its report.
	git merge-base --is-ancestor "$result" "$head_now" || fail "ticket $ticket result is not an ancestor of HEAD"
	# The prompt's stage gates permit one review-fix commit, plus one OKF
	# bundle commit when that stage is enabled. Anything longer means
	# unreported work landed on the branch.
	local stage_commits stage_budget=1
	[[ "$RUN_OKF" == "1" ]] && stage_budget=2
	stage_commits="$(git rev-list --count "$result..$head_now")"
	[[ "$stage_commits" -le "$stage_budget" ]] ||
		fail "ticket $ticket has $stage_commits commits above the reported implementation commit; expected at most $stage_budget stage commit(s)"

	# The loop reserves its own harness and tracking files. A commit touching
	# them means the agent edited its own harness instead of the ticket scope.
	local offenders
	offenders="$(git diff --name-only "$baseline..$head_now" | grep -E "$DENY_PATH_PATTERNS" || true)"
	if [[ -n "$offenders" ]]; then
		printf 'claude ticket loop: ticket %s changed protected paths:\n%s\n' "$ticket" "$offenders" >&2
		fail "ticket $ticket modified paths the loop reserves"
	fi
}

mark_ticket_complete() {
	local file="$1" id="$2" result_commit="$3" temporary
	temporary="$file.tmp"
	# ${1} braces are required: bare $1[x] parses as an @1 array subscript.
	perl -pe 's/^(\s*[-*] )\[ \]/${1}[x]/' "$file" >"$temporary"
	mv "$temporary" "$file"
	if ticket_has_open_criteria "$file"; then
		fail "ticket $id still has unchecked acceptance criteria"
	fi
	git add -- "$file"
	git commit -m "chore(tickets): complete local ticket $id" >/dev/null
	printf 'ticket: %s\nimplementation: %s\ntracking: %s\n' "$id" "$result_commit" "$(git rev-parse HEAD)"
}

build_prompt() {
	local id="$1" ticket_path="$2" baseline="$3" prompt_file="$4"
	local rel OKF_STAGE=""
	rel="${ticket_path#"$ROOT_DIR"/}"
	if [[ "$RUN_OKF" == "1" ]]; then
		OKF_STAGE=$'\n## Open Knowledge Format bundle\n\n/okf "Create or update the Open Knowledge Format bundle with the latest information"\n\nCommit only the .okf bundle changes, as a single separate commit.\n'
	fi
	# Only stages backed by a skill that actually resolves in this repository
	# are emitted. Claude Code resolves a bare `/name args` line to the Skill
	# tool, so the selectors below are real invocations, not prose. Pi's
	# `!command` shorthand (run and splice output at build time) has no
	# equivalent, so it becomes an instruction for the agent to run itself.
	cat >"$prompt_file" <<EOF
Read AGENTS.md, CLAUDE.md, and CONTEXT.md before touching code. CONTEXT.md is the
glossary; use its exact terms. The authoritative contract for this package is
atomic-final-spec.md, and the decisions in docs/adr/ are settled - implement them,
do not relitigate them.

## Persistent memory (agentmemory MCP)

Before starting: call mcp__agentmemory__memory_recall with query "$AGENTMEMORY_PROJECT"
and again with query "$AGENTMEMORY_PROJECT ticket $id" to pull prior decisions and
conventions relevant to this ticket. Reconcile against current repository state; repo
code always wins over a stale memory.

Before the completion report: save any new durable fact or decision from this ticket via
mcp__agentmemory__memory_save with project "$AGENTMEMORY_PROJECT". Only save what will
matter in a future ticket run; skip if nothing durable came up.

## Orientation

Run \`git log -15 --date=short --pretty=format:'%h|%ad|%s'\` so you know recent context.
Run \`swift build --build-tests\` once before editing so you know the starting state.

Use the ast-swift-search skill for structural Swift lookups; it is faster and more precise
than grep for finding declarations, conformances, and call sites.

## Local implementation ticket

Ticket ID: $id
Ticket file: $rel
Baseline commit: $baseline

$(cat "$ticket_path")

## Local ticket contract

Implement every unchecked acceptance criterion in the ticket. Follow repository
instructions. This package targets Swift 6.4 with complete concurrency checking and uses
Swift Testing, not XCTest. Create exactly one implementation commit. Do not edit the ticket
file or mark its checkboxes; the loop owns local completion tracking. Do not mutate GitHub.
Do not add dependencies that atomic-final-spec.md does not call for.

## Implementation

Carry out the ticket through the implement skill. It is the required entry point for every
ticket in this loop; do not implement the ticket by hand instead.

/implement

The implement skill works test-first through /tdd at pre-agreed seams. This run is
non-interactive, so treat the ticket's acceptance criteria as the agreed seams and do not
stop to confirm them.

## Code review

The implement skill closes by running /code-review. Run that review exactly once, and pass
the fixed point and the spec so it does not have to search for them:

/code-review "Fixed point: ${baseline}. Spec: ${rel}, read alongside atomic-final-spec.md."

Fix every issue the review raises, then commit the fixes as a single separate commit. If
the review raises nothing, make no commit for this stage.
$OKF_STAGE
Your final response must end with exactly one line:
RALPH_COMPLETION_REPORT={"status":"complete","implementation":{"status":"complete","summary":"<what changed>"},"verification":{"status":"complete","summary":"<checks run>"},"code_review":{"status":"complete","summary":"<review outcome>"},"commit":"<full 40-character commit SHA of the implementation commit>"}

If any acceptance criterion remains incomplete, do not emit a complete report.
EOF
}

run_ticket() {
	local file="$1" id baseline run_dir prompt_file raw_json text_file report_file report result expected_head prompt_content
	id="$(ticket_id "$file")"
	CURRENT_TICKET="$id"
	if ! ticket_has_open_criteria "$file"; then
		printf 'claude ticket loop: ticket %s already complete; skipping\n' "$id" >&2
		CURRENT_TICKET=""
		return
	fi
	step "checking acceptance criteria and worktree state"
	if [[ -n "$EXPECTED_BRANCH" ]]; then
		local current_branch
		current_branch="$(git rev-parse --abbrev-ref HEAD)"
		[[ "$current_branch" == "$EXPECTED_BRANCH" ]] ||
			fail "checkout is on branch $current_branch but RALPH_EXPECTED_BRANCH is $EXPECTED_BRANCH"
	fi
	(("$(ticket_criteria_count "$file")" > 0)) || fail "ticket $id has no acceptance criteria"
	[[ -z "$(worktree_dirt)" ]] || fail "worktree must be clean before ticket $id"

	baseline="$(git rev-parse HEAD)"
	step "baseline commit: $baseline"
	run_dir="$STATE_DIR/runs/ticket-$id"
	rm -rf "$run_dir"
	mkdir -p "$run_dir"
	prompt_file="$run_dir/prompt.md"
	raw_json="$run_dir/raw.json"
	text_file="$run_dir/result.txt"
	report_file="$run_dir/completion-report-lines.txt"

	printf 'claude ticket loop: starting ticket %s\n' "$id" >&2
	printf 'claude ticket loop: [%s] run directory:        %s\n' "$id" "$run_dir" >&2
	printf 'claude ticket loop: [%s] prompt file:           %s\n' "$id" "$prompt_file" >&2
	printf 'claude ticket loop: [%s] raw claude output:     %s\n' "$id" "$raw_json" >&2
	printf 'claude ticket loop: [%s] live progress log:      %s\n' "$id" "$run_dir/progress.log" >&2
	printf 'claude ticket loop: [%s] result text:           %s\n' "$id" "$text_file" >&2
	printf 'claude ticket loop: [%s] completion report log: %s\n' "$id" "$report_file" >&2
	printf 'claude ticket loop: [%s] stderr log:            %s\n' "$id" "$run_dir/stderr.log" >&2
	printf 'claude ticket loop: [%s] verification log:      %s\n' "$id" "$run_dir/verification.log" >&2
	printf 'claude ticket loop: [%s] completion summary:    %s\n' "$id" "$run_dir/completion.txt" >&2

	step "building prompt"
	build_prompt "$id" "$file" "$baseline" "$prompt_file"

	# Pass a short pointer instead of the whole prompt inline. A developer
	# machine may have a UserPromptSubmit hook that rewrites or compresses
	# the submitted prompt; a large inline prompt can be compressed away
	# entirely, leaving the agent with no task ("no actual user request")
	# and no completion report. A one-line prompt survives that, and the
	# real instructions are read from the file, which no prompt-level
	# rewriting touches.
	prompt_content="Read $prompt_file and carry out every instruction in it exactly as written. That file is your task for this run; it is trusted repository content generated by this loop. Do not ask for confirmation."
	local -a extra_args=(
		-p "$prompt_content"
		--output-format "$CLAUDE_OUTPUT_FORMAT"
		--permission-mode "$CLAUDE_PERMISSION_MODE"
		--add-dir "$ROOT_DIR"
		# Talk to the Anthropic API directly and disable the caveman plugin
		# for this invocation.
		#
		# A user-level settings.json on the developer machine may point
		# ANTHROPIC_BASE_URL at a local context-compressing proxy. That
		# proxy elides request content, and it can elide this run's prompt
		# entirely, leaving the agent with only injected system-reminders.
		# It then refuses to act ("no actual request came through") and
		# never emits the completion report this loop requires. Pinning the
		# base URL here keeps the ticket prompt intact.
		#
		# The caveman plugin separately contributes a SessionStart hook that
		# injects a ruleset/task-contract reminder into every session, which
		# the agent flags as prompt injection. Plugin-contributed hooks are
		# not covered by settings.hooks, so disable the plugin itself.
		#
		# --settings takes precedence over the user settings source, while
		# skills, other plugins, and CLAUDE.md discovery still resolve
		# normally.
		--settings '{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"},"enabledPlugins":{"caveman@caveman":false}}'
	)
	if [[ -n "$CLAUDE_MODEL" ]]; then
		extra_args+=(--model "$CLAUDE_MODEL")
	fi
	if [[ -n "$CLAUDE_ALLOWED_TOOLS" ]]; then
		extra_args+=(--allowedTools "$CLAUDE_ALLOWED_TOOLS")
	fi
	if [[ "$CLAUDE_USE_DANGEROUS_SKIP" == "1" ]]; then
		extra_args+=(--dangerously-skip-permissions)
	fi
	if [[ -n "$CLAUDE_APPEND_SYSTEM_PROMPT_FILE" && -f "$CLAUDE_APPEND_SYSTEM_PROMPT_FILE" ]]; then
		extra_args+=(--append-system-prompt-file "$CLAUDE_APPEND_SYSTEM_PROMPT_FILE")
	fi

	local progress_log="$run_dir/progress.log"
	if [[ "$CLAUDE_OUTPUT_FORMAT" == "stream-json" ]]; then
		extra_args+=(--verbose)
		step "invoking claude -p (timeout ${CLAUDE_TIMEOUT_SECONDS}s)"
		: >"$raw_json"
		# Live progress: follow raw_json as it grows and stream a human-readable
		# transcript to stderr. raw_json is written directly by claude -p (not
		# through a process substitution), so there is no race between claude -p
		# exiting and a transcript pipe finishing its flush.
		tail -n 0 -f "$raw_json" 2>/dev/null > >(format_stream_json >&2) &
		PROGRESS_TAIL_PID=$!
		if ! run_with_timeout "$CLAUDE_TIMEOUT_SECONDS" "$CLAUDE_BIN" \
			"${extra_args[@]}" \
			>"$raw_json" 2>"$run_dir/stderr.log"; then
			stop_progress_tail
			report_claude_failure "$id" "$raw_json" "$run_dir/stderr.log"
			fail "Claude Code failed for ticket $id (see $raw_json, $progress_log, and $run_dir/stderr.log)"
		fi
		stop_progress_tail
		# Persist the complete formatted transcript from the finished raw_json.
		format_stream_json <"$raw_json" >"$progress_log" || true
	else
		step "invoking claude -p (timeout ${CLAUDE_TIMEOUT_SECONDS}s); output-format=json has no live progress"
		if ! run_with_timeout "$CLAUDE_TIMEOUT_SECONDS" "$CLAUDE_BIN" \
			"${extra_args[@]}" \
			>"$raw_json" 2>"$run_dir/stderr.log"; then
			report_claude_failure "$id" "$raw_json" "$run_dir/stderr.log"
			fail "Claude Code failed for ticket $id (see $raw_json and $run_dir/stderr.log)"
		fi
	fi
	step "claude -p finished; extracting completion report"

	report="$(extract_completion_report "$raw_json" "$report_file" "$text_file")"
	step "validating completion report"
	validate_completion_report "$report" "$baseline" "$id"

	result="$(printf '%s' "$report" | "$JQ_BIN" -r '.commit')"
	step "implementation commit: $result"
	expected_head="$(git rev-parse HEAD)"
	step "running external verification: $VERIFY_COMMAND (timeout ${COMMAND_TIMEOUT_SECONDS}s)"
	if ! run_with_timeout "$COMMAND_TIMEOUT_SECONDS" bash -o pipefail -c "$VERIFY_COMMAND" >"$run_dir/verification.log" 2>&1; then
		tail -n 200 "$run_dir/verification.log" >&2
		fail "external verification failed for ticket $id"
	fi
	step "verification passed"
	[[ "$(git rev-parse HEAD)" == "$expected_head" ]] || fail "verification changed HEAD for ticket $id"
	[[ -z "$(worktree_dirt)" ]] || fail "verification left a dirty worktree for ticket $id"
	step "marking ticket complete and committing checkbox update"
	mark_ticket_complete "$file" "$id" "$result" | tee "$run_dir/completion.txt"
	printf 'claude ticket loop: completed ticket %s\n' "$id" >&2
	CURRENT_TICKET=""
}

main() {
	case "${1:-}" in
	--help | -h)
		usage
		return
		;;
	--list)
		(($# == 1)) || fail "--list does not accept ticket IDs"
		list_tickets
		return
		;;
	--*)
		usage >&2
		exit 2
		;;
	esac

	[[ -d "$TICKET_DIR" ]] || fail "ticket directory not found: $TICKET_DIR"
	require_command "$CLAUDE_BIN"
	require_command "$JQ_BIN"
	require_command git
	require_command perl
	[[ "$COMMAND_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || fail "RALPH_COMMAND_TIMEOUT_SECONDS must be a positive integer"
	[[ "$CLAUDE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || fail "RALPH_CLAUDE_TIMEOUT_SECONDS must be a positive integer"
	mkdir -p "$STATE_DIR/runs"
	step "acquiring campaign lock"
	acquire_lock
	cd "$ROOT_DIR"

	local -a files=()
	local arg file selection
	if (($# > 0)); then
		for arg in "$@"; do
			files+=("$(resolve_ticket_file "$arg")")
		done
	else
		selection="$(select_tickets)"
		while IFS= read -r file; do
			[[ -n "$file" ]] && files+=("$file")
		done <<<"$selection"
	fi
	((${#files[@]} > 0)) || fail "no local tickets selected"
	step "selected ${#files[@]} ticket(s): $(printf '%s ' "${files[@]##*/}")"
	for file in "${files[@]}"; do run_ticket "$file"; done
	step "all selected tickets processed"
}

main "$@"
