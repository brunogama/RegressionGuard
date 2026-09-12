#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

repository="$temporary_directory/repository"
mkdir -p "$repository/scripts/local-ticket-loop" "$repository/.scratch/tickets" "$repository/.pi/skills/tdd"
cp "$SOURCE_DIR/loop.sh" "$repository/scripts/local-ticket-loop/loop.sh"
printf '%s\n' '# isolated test skill' >"$repository/.pi/skills/tdd/SKILL.md"
cat >"$repository/.scratch/tickets/99.md" <<'EOF'
## Acceptance criteria

- [ ] Exercise the Pi RPC invocation.
EOF
cat >"$repository/fake-rpc-stream" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$RPC_ARGUMENTS_FILE"
exit 1
EOF
chmod +x "$repository/fake-rpc-stream" "$repository/scripts/local-ticket-loop/loop.sh"

git -C "$repository" init -q
git -C "$repository" config user.name "Local Loop Test"
git -C "$repository" config user.email "local-loop-test@example.invalid"
git -C "$repository" add .
git -C "$repository" commit -qm "test fixture"

arguments_file="$temporary_directory/rpc-arguments.txt"
set +e
RALPH_EXPLORE=0 \
RPC_ARGUMENTS_FILE="$arguments_file" \
	PI_BIN=true \
	RPC_STREAM_BIN="$repository/fake-rpc-stream" \
	RALPH_PI_TIMEOUT_SECONDS=5 \
	RALPH_PROMPT_DIR="$SOURCE_DIR" \
	"$repository/scripts/local-ticket-loop/loop.sh" 99 >"$temporary_directory/stdout" 2>"$temporary_directory/stderr"
status=$?

PI_BIN=true \
	RPC_STREAM_BIN="$repository/fake-rpc-stream" \
	RALPH_PROMPT_DIR="$SOURCE_DIR" \
	"$repository/scripts/local-ticket-loop/loop.sh" --dry-run 99 \
	>"$temporary_directory/dry-run-stdout" \
	2>"$temporary_directory/dry-run-stderr"
grep -F -- 'verify default: swift build --build-tests && swift test' "$temporary_directory/dry-run-stderr" >/dev/null || {
	printf 'loop.sh dry-run did not report the Swift verification default\n' >&2
	exit 1
}
grep -F -- 'swift build --build-tests && swift test' "$temporary_directory/dry-run-stdout" >/dev/null || {
	printf 'loop.sh dry-run did not resolve the Swift verification default\n' >&2
	exit 1
}

"$repository/scripts/local-ticket-loop/loop.sh" --help >"$temporary_directory/loop-help"
grep -F -- 'default: swift build --build-tests && swift test' "$temporary_directory/loop-help" >/dev/null || {
	printf 'loop.sh help did not document the Swift verification default\n' >&2
	exit 1
}
set -e

[[ "$status" == 1 ]] || {
	printf 'expected loop to propagate fake RPC failure, got %s\n' "$status" >&2
	exit 1
}
grep -Fx -- '--no-extensions' "$arguments_file" >/dev/null || {
	printf 'Pi invocation did not disable ambient extension discovery\n' >&2
	exit 1
}
grep -Fx -- '--no-input' "$arguments_file" >/dev/null || {
	printf 'Pi invocation did not disable terminal input for unattended execution\n' >&2
	cat "$arguments_file" >&2
	exit 1
}
if grep -Fx -- '--approve' "$arguments_file" >/dev/null; then
	printf 'Pi invocation still uses unsupported --approve flag\n' >&2
	cat "$arguments_file" >&2
	exit 1
fi
if grep -Fx -- '--name' "$arguments_file" >/dev/null; then
	printf 'Pi invocation still uses unsupported --name flag\n' >&2
	cat "$arguments_file" >&2
	exit 1
fi
grep -Fx -- '--session-dir' "$arguments_file" >/dev/null || {
	printf 'Pi invocation did not retain --session-dir for phase isolation\n' >&2
	cat "$arguments_file" >&2
	exit 1
}
expected_skill_path="$(git -C "$repository" rev-parse --show-toplevel)/.pi/skills/tdd/SKILL.md"
grep -Fx -- "$expected_skill_path" "$arguments_file" >/dev/null || {
	printf 'Pi invocation did not load skills from the active repository\n' >&2
	cat "$arguments_file" >&2
	exit 1
}
if grep -Fx -- '--immediate-format' "$arguments_file" >/dev/null; then
	printf 'Pi invocation still uses the RPC-incompatible --immediate-format flag\n' >&2
	exit 1
fi

printf 'loop.sh: Pi RPC invocation test passed\n'

# Parallel worktrees have distinct campaign locks, but every Pi process uses the
# same host installation. Exercise the public loop CLI from two linked
# worktrees and make overlap at the fake RPC boundary observable.
parallel_worktree_a="$temporary_directory/pi-lock-worktree-a"
parallel_worktree_b="$temporary_directory/pi-lock-worktree-b"
git -C "$repository" worktree add -q -b "pi-lock-test-a-$$" "$parallel_worktree_a" HEAD
git -C "$repository" worktree add -q -b "pi-lock-test-b-$$" "$parallel_worktree_b" HEAD

pi_lock_file="$temporary_directory/pi-host.lock"
pi_lock_critical_directory="$temporary_directory/pi-critical"
pi_lock_events="$temporary_directory/pi-lock-events"
pi_lock_overlap="$temporary_directory/pi-lock-overlap"
pi_lock_release="$temporary_directory/pi-lock-release"
pi_lock_start="$temporary_directory/pi-lock-start"
# A leftover lock file has no live BSD lock and must be safe to reacquire.
printf 'stale owner\n' >"$pi_lock_file"
: >"$pi_lock_events"

cat >"$temporary_directory/fake-lock-rpc-stream" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if ! mkdir "$PI_LOCK_TEST_CRITICAL_DIRECTORY" 2>/dev/null; then
	printf '%s\n' "$PI_LOCK_TEST_INVOCATION" >>"$PI_LOCK_TEST_OVERLAP"
	exit 1
fi
cleanup() {
	rmdir "$PI_LOCK_TEST_CRITICAL_DIRECTORY" 2>/dev/null || true
}
trap cleanup EXIT

printf 'enter %s\n' "$PI_LOCK_TEST_INVOCATION" >>"$PI_LOCK_TEST_EVENTS"
attempt=0
while [[ ! -e "$PI_LOCK_TEST_RELEASE" ]]; do
	attempt=$((attempt + 1))
	((attempt < 1000)) || {
		printf 'fake RPC timed out waiting for release\n' >&2
		exit 1
	}
	sleep 0.01
done
printf 'exit %s\n' "$PI_LOCK_TEST_INVOCATION" >>"$PI_LOCK_TEST_EVENTS"
exit 1
EOF
chmod +x "$temporary_directory/fake-lock-rpc-stream"

run_pi_lock_fixture() {
	local worktree="$1" invocation="$2" stdout_file="$3" stderr_file="$4"
	while [[ ! -e "$pi_lock_start" ]]; do sleep 0.01; done
	RALPH_EXPLORE=0 \
		PI_BIN=true \
		RPC_STREAM_BIN="$temporary_directory/fake-lock-rpc-stream" \
		RALPH_PI_LOCK_FILE="$pi_lock_file" \
		RALPH_PI_TIMEOUT_SECONDS=10 \
		RALPH_PROMPT_DIR="$SOURCE_DIR" \
		PI_LOCK_TEST_INVOCATION="$invocation" \
		PI_LOCK_TEST_CRITICAL_DIRECTORY="$pi_lock_critical_directory" \
		PI_LOCK_TEST_EVENTS="$pi_lock_events" \
		PI_LOCK_TEST_OVERLAP="$pi_lock_overlap" \
		PI_LOCK_TEST_RELEASE="$pi_lock_release" \
		"$worktree/scripts/local-ticket-loop/loop.sh" 99 \
		>"$stdout_file" 2>"$stderr_file"
}

set +e
run_pi_lock_fixture "$parallel_worktree_a" a \
	"$temporary_directory/pi-lock-a-stdout" "$temporary_directory/pi-lock-a-stderr" &
pi_lock_pid_a=$!
run_pi_lock_fixture "$parallel_worktree_b" b \
	"$temporary_directory/pi-lock-b-stdout" "$temporary_directory/pi-lock-b-stderr" &
pi_lock_pid_b=$!
set -e
touch "$pi_lock_start"

pi_lock_ready=0
for _ in $(seq 1 1000); do
	entered_count="$(grep -c '^enter ' "$pi_lock_events" 2>/dev/null || true)"
	if [[ -e "$pi_lock_overlap" ]] || {
		[[ "$entered_count" -ge 1 ]] &&
			grep -Fq 'waiting for host-wide Pi lock' "$temporary_directory/pi-lock-a-stderr" 2>/dev/null &&
			grep -Fq 'waiting for host-wide Pi lock' "$temporary_directory/pi-lock-b-stderr" 2>/dev/null
	}; then
		pi_lock_ready=1
		break
	fi
	sleep 0.01
done
touch "$pi_lock_release"

set +e
wait "$pi_lock_pid_a"
pi_lock_status_a=$?
wait "$pi_lock_pid_b"
pi_lock_status_b=$?
set -e

[[ "$pi_lock_ready" == 1 ]] || {
	printf 'parallel loop invocations did not reach the Pi lock boundary\n' >&2
	exit 1
}
[[ "$pi_lock_status_a" == 1 && "$pi_lock_status_b" == 1 ]] || {
	printf 'expected both fake RPC failures to propagate, got %s and %s\n' \
		"$pi_lock_status_a" "$pi_lock_status_b" >&2
	exit 1
}
[[ ! -e "$pi_lock_overlap" ]] || {
	printf 'parallel Pi critical sections overlapped\n' >&2
	cat "$pi_lock_overlap" >&2
	exit 1
}

for stderr_file in \
	"$temporary_directory/pi-lock-a-stderr" \
	"$temporary_directory/pi-lock-b-stderr"; do
	grep -Fq 'waiting for host-wide Pi lock' "$stderr_file" || {
		printf 'Pi lock did not report its waiting state\n' >&2
		exit 1
	}
	grep -Fq 'acquired host-wide Pi lock' "$stderr_file" || {
		printf 'Pi lock did not report acquisition\n' >&2
		exit 1
	}
	grep -Fq 'released host-wide Pi lock' "$stderr_file" || {
		printf 'Pi lock did not report release\n' >&2
		exit 1
	}
done

awk '
	$1 == "enter" { depth += 1; enters += 1; if (depth > maximum) maximum = depth }
	$1 == "exit" { depth -= 1; exits += 1; if (depth < 0) exit 1 }
	END { if (enters != 2 || exits != 2 || maximum != 1 || depth != 0) exit 1 }
' "$pi_lock_events" || {
	printf 'unexpected Pi critical-section event order:\n' >&2
	cat "$pi_lock_events" >&2
	exit 1
}

# A later public invocation must reacquire after both prior processes exit.
set +e
run_pi_lock_fixture "$parallel_worktree_a" reacquired \
	"$temporary_directory/pi-lock-reacquired-stdout" \
	"$temporary_directory/pi-lock-reacquired-stderr"
pi_lock_reacquired_status=$?
set -e
[[ "$pi_lock_reacquired_status" == 1 ]] || {
	printf 'expected reacquired fake RPC failure to propagate, got %s\n' \
		"$pi_lock_reacquired_status" >&2
	exit 1
}
grep -Fq 'acquired host-wide Pi lock' "$temporary_directory/pi-lock-reacquired-stderr" || {
	printf 'Pi lock was not reacquired after prior loop exit\n' >&2
	exit 1
}
[[ "$(grep -c '^enter ' "$pi_lock_events")" == 3 ]] || {
	printf 'expected three serialized Pi entries after reacquisition\n' >&2
	exit 1
}

printf 'loop.sh: host-wide Pi lock concurrency test passed\n'

# A provider transport error that Pi successfully retries is historical, not
# a terminal failure. The loop must accept the later successful completion.
cat >"$temporary_directory/fake-recovered-rpc-stream" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log_file=""
prompt_file=""
while (($# > 0)); do
	case "$1" in
	--log) log_file="$2"; shift 2 ;;
	--prompt-file) prompt_file="$2"; shift 2 ;;
	*) shift ;;
	esac
done
if grep -q '^## Review lens:' "$prompt_file"; then
	lens="$(sed -n 's/^## Review lens: //p' "$prompt_file")"
	critic_report="$(jq -nc --arg lens "$lens" '{lens:$lens,blockers:[],nits:[]}')"
	jq -nc --arg report "$critic_report" '{type:"message_end",message:{role:"assistant",content:[{type:"text",text:$report}],stopReason:"stop"}}' >"$log_file"
	exit 0
fi
count="$(cat "$RPC_RECOVERY_COUNTER" 2>/dev/null || printf '0')"
count=$((count + 1))
printf '%s' "$count" >"$RPC_RECOVERY_COUNTER"
if ((count == 1)); then
	printf 'implementation\n' >implementation.txt
	git add implementation.txt
	git commit -qm "feat: fake recovered implementation"
fi
commit="$(git rev-parse HEAD)"
report="$(jq -nc --arg commit "$commit" '{
	status: "complete",
	implementation: {status: "complete"},
	verification: {status: "complete"},
	code_review: {status: "complete"},
	commit: $commit,
	criteria_total: 1,
	criteria_open: 1,
	criteria_satisfied: 1,
	files_changed: ["implementation.txt"]
}')"
if ((count == 1)); then
	jq -nc '{type:"message_end",message:{role:"assistant",content:[],stopReason:"error",errorMessage:"WebSocket error"}}' >"$log_file"
	jq -nc '{type:"auto_retry_start",attempt:1,maxAttempts:3,delayMs:1,errorMessage:"WebSocket error"}' >>"$log_file"
	jq -nc '{type:"auto_retry_end",success:true,attempt:1}' >>"$log_file"
	jq -nc '{type:"message_end",message:{role:"assistant",content:[{type:"text",text:"implementation committed, but report omitted"}],stopReason:"stop"}}' >>"$log_file"
else
	jq -nc --arg report "$report" '{type:"message_end",message:{role:"assistant",content:[{type:"text",text:("RALPH_COMPLETION_REPORT=" + $report)}],stopReason:"stop"}}' >"$log_file"
fi
EOF
chmod +x "$temporary_directory/fake-recovered-rpc-stream"
RALPH_EXPLORE=0 \
RPC_RECOVERY_COUNTER="$temporary_directory/rpc-recovery-counter" \
RALPH_OKF=0 \
RALPH_VERIFY_COMMAND=true \
PI_BIN=true \
RPC_STREAM_BIN="$temporary_directory/fake-recovered-rpc-stream" \
RALPH_PROMPT_DIR="$SOURCE_DIR" \
"$repository/scripts/local-ticket-loop/loop.sh" 99 \
	>"$temporary_directory/recovered-stdout" 2>"$temporary_directory/recovered-stderr" || {
	printf 'loop.sh rejected a successfully recovered provider error\n' >&2
	cat "$temporary_directory/recovered-stderr" >&2
	exit 1
}
grep -Fq 'ticket: 99' "$temporary_directory/recovered-stdout" || {
	printf 'loop.sh did not complete after the recovered provider error\n' >&2
	exit 1
}

printf 'loop.sh: recovered provider retry test passed\n'
# --- loop-claude.sh: full success path through a fake `claude` binary ---------

claude_repository="$temporary_directory/claude-repository"
mkdir -p "$claude_repository/scripts/local-ticket-loop/shared" "$claude_repository/.scratch/deep-research-package/issues"
cp "$SOURCE_DIR/loop-claude.sh" "$claude_repository/scripts/local-ticket-loop/loop-claude.sh"
cp "$SOURCE_DIR/shared/process.sh" "$claude_repository/scripts/local-ticket-loop/shared/process.sh"
chmod +x "$claude_repository/scripts/local-ticket-loop/loop-claude.sh"

cat >"$claude_repository/.scratch/deep-research-package/issues/99.md" <<'EOF'
## Acceptance criteria

- [ ] Exercise the Claude Code invocation.
- [ ] Exercise the completion bookkeeping.
EOF

# Stands in for `claude -p`: makes one real commit, then emits the JSON
# envelope the loop parses, carrying a valid completion report.
cat >"$temporary_directory/fake-claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'implementation\n' >>implementation.txt
git add implementation.txt
git commit -qm "feat: fake implementation"
report="RALPH_COMPLETION_REPORT=$(jq -nc --arg sha "$(git rev-parse HEAD)" '{
	status: "complete",
	implementation: {status: "complete", summary: "implemented"},
	verification: {status: "complete", summary: "focused checks"},
	code_review: {status: "complete", summary: "clean"},
	commit: $sha
}')"
jq -n -c --arg result "narration
$report" '{type: "result", subtype: "success", is_error: false, result: $result}'
EOF
chmod +x "$temporary_directory/fake-claude"

git -C "$claude_repository" init -q
git -C "$claude_repository" config user.name "Local Loop Test"
git -C "$claude_repository" config user.email "local-loop-test@example.invalid"
git -C "$claude_repository" add .
git -C "$claude_repository" commit -qm "test fixture"

mkdir -p "$temporary_directory/fake-bin"
cat >"$temporary_directory/fake-bin/swift" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SWIFT_INVOCATIONS_FILE"
EOF
chmod +x "$temporary_directory/fake-bin/swift"

"$claude_repository/scripts/local-ticket-loop/loop-claude.sh" --help >"$temporary_directory/loop-claude-help"
grep -F -- 'default: swift build --build-tests && swift test' "$temporary_directory/loop-claude-help" >/dev/null || {
	printf 'loop-claude.sh help did not document the Swift verification default\n' >&2
	exit 1
}

swift_invocations_file="$temporary_directory/swift-invocations.txt"
(
	cd "$claude_repository"
	PATH="$temporary_directory/fake-bin:$PATH" \
		CLAUDE_BIN="$temporary_directory/fake-claude" \
		SWIFT_INVOCATIONS_FILE="$swift_invocations_file" \
		RALPH_CLAUDE_TIMEOUT_SECONDS=60 \
		./scripts/local-ticket-loop/loop-claude.sh 99 \
		>"$temporary_directory/claude-stdout" 2>"$temporary_directory/claude-stderr"
) || {
	printf 'loop-claude.sh failed on the success path\n' >&2
	cat "$temporary_directory/claude-stderr" >&2
	exit 1
}

grep -Fx -- 'build --build-tests' "$swift_invocations_file" >/dev/null || {
	printf 'loop-claude.sh did not run the Swift build default\n' >&2
	exit 1
}
grep -Fx -- 'test' "$swift_invocations_file" >/dev/null || {
	printf 'loop-claude.sh did not run the Swift test default\n' >&2
	exit 1
}

completed_ticket="$claude_repository/.scratch/deep-research-package/issues/99.md"
# Regression: `$1[x]` parses as an @1 subscript in Perl and silently deletes
# the whole `- [ ] ` prefix instead of ticking it.
checked_count="$(grep -cE '^- \[x\] ' "$completed_ticket" || true)"
[[ "$checked_count" == 2 ]] || {
	printf 'expected 2 ticked acceptance criteria, found %s:\n' "$checked_count" >&2
	cat "$completed_ticket" >&2
	exit 1
}
if grep -qE '^ \S' "$completed_ticket"; then
	printf 'completion rewrite stripped acceptance-criteria list markers\n' >&2
	cat "$completed_ticket" >&2
	exit 1
fi
[[ -z "$(git -C "$claude_repository" status --porcelain)" ]] || {
	printf 'loop-claude.sh left a dirty worktree\n' >&2
	exit 1
}
git -C "$claude_repository" log -1 --pretty=%s | grep -Fxq 'chore(tickets): complete local ticket 99' || {
	printf 'loop-claude.sh did not create the tracking commit\n' >&2
	exit 1
}

printf 'loop-claude.sh: success-path test passed\n'
printf 'local ticket loop tests passed\n'
