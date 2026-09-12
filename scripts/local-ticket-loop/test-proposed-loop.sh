#!/usr/bin/env bash
# Isolated regression check for proposed-loop.sh.
#
# Builds a throwaway Git repository with the real ticket filenames, substitutes
# a fake per-ticket loop, and exercises the orchestrator end to end: parallel
# execution inside a wave, sequential merge integration, conflict repair, the
# WORKTREE_ROOT confinement guard, and the no-commit rejection.
set -euo pipefail

SOURCE_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR
readonly TICKET_RELATIVE_DIR=".scratch/tickets"

temporary_directory="$(mktemp -d)"
cleanup() {
	if [[ "${KEEP_TEST_DIRECTORY:-0}" == 1 ]]; then
		printf 'retained test directory: %s\n' "$temporary_directory" >&2
	else
		rm -rf "$temporary_directory"
	fi
}
trap cleanup EXIT

repository="$temporary_directory/repository"
worktree_root="$temporary_directory/worktrees"
mkdir -p "$repository/scripts/local-ticket-loop"
mkdir -p "$repository/scripts/local-ticket-loop/shared"
mkdir -p "$repository/$TICKET_RELATIVE_DIR"

cp "$SOURCE_DIR/proposed-loop.sh" "$repository/scripts/local-ticket-loop/proposed-loop.sh"
cp "$SOURCE_DIR/shared/process.sh" "$repository/scripts/local-ticket-loop/shared/process.sh"

# Fake per-ticket loop. Every ticket in a multi-ticket wave registers at a
# filesystem barrier before doing any work, so the test fails if the
# orchestrator ever serializes a wave it promised to run in parallel.
cat >"$repository/scripts/local-ticket-loop/loop.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ticket="$1"

expected=1
wave=single
case "$ticket" in
02-* | 06-*) expected=2; wave=wave-2 ;;
03-* | 07-* | 08-* | 15-*) expected=4; wave=wave-3 ;;
esac

# Register before deciding whether there is work to do. A resumed wave relaunches
# every ticket that is still open at the campaign baseline, including ones whose
# own branch already finished them; if those exited without registering, the
# tickets still working would wait for a quorum that can never arrive.
if ((expected > 1)); then
	mkdir -p "$BARRIER_DIRECTORY/$wave"
	touch "$BARRIER_DIRECTORY/$wave/$ticket"
fi

if ! grep -qE '^[[:space:]]*[-*] \[ \]' "$LOCAL_TICKET_DIR/$ticket.md"; then
	exit 0
fi
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$RALPH_EXPECTED_BRANCH" ]]
if [[ "${NO_CHANGE_TICKET:-}" == "$ticket" ]]; then
	exit 0
fi
if [[ "${FAIL_TICKET:-}" == "$ticket" ]]; then
	# Die the way an interrupted agent does: work on disk, nothing committed.
	printf 'interrupted %s\n' "$ticket" >"interrupted-$ticket.txt"
	exit 1
fi
if ((expected > 1)); then
	attempt=0
	while :; do
		arrivals="$(find "$BARRIER_DIRECTORY/$wave" -type f | wc -l | tr -d ' ')"
		((arrivals >= expected)) && break
		attempt=$((attempt + 1))
		((attempt < 200)) || {
			printf 'parallel barrier timed out for %s\n' "$ticket" >&2
			exit 1
		}
		sleep 0.05
	done
fi

printf 'implemented %s\n' "$ticket" >"implemented-$ticket.txt"
# Every ticket rewrites the same single-line file, so the second and later
# merges inside a wave conflict and exercise the repair path.
printf 'tickets=%s\n' "$ticket" >shared-ticket-registry.txt
perl -pi -e 's/\[ \]/[x]/' "$LOCAL_TICKET_DIR/$ticket.md"
git add "implemented-$ticket.txt" shared-ticket-registry.txt "$LOCAL_TICKET_DIR/$ticket.md"
git commit -qm "test: implement $ticket"
EOF
chmod +x "$repository/scripts/local-ticket-loop/loop.sh"
chmod +x "$repository/scripts/local-ticket-loop/proposed-loop.sh"

tickets=(
	01-fidelity-layer
	02-walking-skeleton-run
	03-search-document-evidence
	04-claims-reconciliation
	05-cited-answer
	06-http-transport
	07-exa-adapter
	08-anthropic-adapter
	09-budget-ledger-reservations
	10-deterministic-scheduling
	11-iterative-loop
	12-pause-cancel-concurrent-runs
	13-context-budget-summarization
	14-cache
	15-retry-error-mapping
	16-security-redaction-telemetry
)

for ticket in "${tickets[@]}"; do
	case "$ticket" in
	01-*) blockers="none" ;;
	02-*) blockers="01" ;;
	03-*) blockers="02" ;;
	04-*) blockers="03" ;;
	05-*) blockers="04" ;;
	06-*) blockers="01" ;;
	07-* | 08-* | 15-*) blockers="06" ;;
	09-* | 14-*) blockers="03" ;;
	10-*) blockers="09" ;;
	11-*) blockers="04, 10" ;;
	12-*) blockers="10" ;;
	13-*) blockers="05" ;;
	16-*) blockers="05, 06" ;;
	*) blockers="none" ;;
	esac
	cat >"$repository/$TICKET_RELATIVE_DIR/$ticket.md" <<EOF
# $ticket

Blocked by: $blockers

- [ ] Test criterion.
EOF
done
# Ticket 01 starts complete, so the run also covers the already-done skip path.
perl -pi -e 's/\[ \]/[x]/' "$repository/$TICKET_RELATIVE_DIR/01-fidelity-layer.md"

printf 'tickets=\n' >"$repository/shared-ticket-registry.txt"

# Conflict resolver: union the ticket names present in the conflicted file,
# then complete the merge. proposed-loop.sh requires a clean worktree after
# repair, so the resolver must commit.
conflict_resolver="$temporary_directory/resolve-wave-conflict.sh"
cat >"$conflict_resolver" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import re

path = Path("shared-ticket-registry.txt")
tickets = sorted(set(re.findall(r"[0-9]{2}-[a-z0-9-]+", path.read_text())))
path.write_text(f"tickets={','.join(tickets)}\n")
PY
git add -A
git commit -q --no-edit
EOF
chmod +x "$conflict_resolver"

git -C "$repository" init -q -b main
git -C "$repository" config user.name "Proposed Loop Test"
git -C "$repository" config user.email "proposed-loop-test@example.invalid"
git -C "$repository" add .
git -C "$repository" add scripts/local-ticket-loop/shared/process.sh
git -C "$repository" commit -qm "test fixture"

git -C "$repository" branch feat/debtmap
campaign_id="proposed-loop-test-$$"
(
	cd "$repository"
	LOOP_RELATIVE_PATH=scripts/local-ticket-loop/loop-claude.sh \
		BARRIER_DIRECTORY="$temporary_directory/barriers-main" \
		CAMPAIGN_ID="$campaign_id" \
		WORKTREE_ROOT="$worktree_root" \
		INTEGRATION_REPAIR_COMMAND="$conflict_resolver" \
		TICKET_VERIFY_COMMAND=true \
		INTEGRATION_VERIFY_COMMAND=true \
		./scripts/local-ticket-loop/proposed-loop.sh
) >"$temporary_directory/stdout" 2>"$temporary_directory/stderr" || {
	cat "$temporary_directory/stderr" >&2
	exit 1
}

grep -Fq 'Campaign complete.' "$temporary_directory/stdout"

integration_branch="local-ticket-loop/$campaign_id/integration"
integration_commit="$(git -C "$repository" rev-parse --verify "refs/heads/$integration_branch^{commit}")"
[[ "$integration_commit" =~ ^[0-9a-f]{40}$ ]]
[[ "$(git -C "$repository" rev-parse --verify refs/heads/feat/debtmap)" == "$integration_commit" ]] || {
	printf 'campaign did not merge back to feat/debtmap\n' >&2
	exit 1
}
[[ "$(git -C "$repository" rev-parse --verify refs/heads/main)" != "$integration_commit" ]] || {
	printf 'campaign unexpectedly advanced main\n' >&2
	exit 1
}

# Wave 3 holds four tickets, so it must produce four sequential merge commits.
wave_three_merges="$(git -C "$repository" log --format=%s "$integration_commit" |
	grep -c "campaign $campaign_id wave 3 ticket " || true)"
[[ "$wave_three_merges" == 4 ]] || {
	printf 'expected 4 wave-3 merge commits, found %s\n' "$wave_three_merges" >&2
	exit 1
}

# Nothing may be dropped across waves or conflict repairs. Ticket 01 was
# already complete, so its marker is the only one that must be absent.
for ticket in "${tickets[@]}"; do
	if [[ "$ticket" == 01-* ]]; then
		! git -C "$repository" cat-file -e "$integration_commit:implemented-$ticket.txt" 2>/dev/null || {
			printf 'already-complete ticket %s was executed anyway\n' "$ticket" >&2
			exit 1
		}
		continue
	fi
	git -C "$repository" cat-file -e "$integration_commit:implemented-$ticket.txt" 2>/dev/null || {
		printf 'integration lost the marker for ticket %s\n' "$ticket" >&2
		exit 1
	}
	git -C "$repository" show "$integration_commit:$TICKET_RELATIVE_DIR/$ticket.md" |
		grep -qE '^[[:space:]]*[-*] \[ \]' && {
		printf 'integration lost the completed state for ticket %s\n' "$ticket" >&2
		exit 1
	}
done

# The final wave holds four tickets, so its repairs must have unioned all four.
expected_registry='tickets=11-iterative-loop,12-pause-cancel-concurrent-runs,13-context-budget-summarization,16-security-redaction-telemetry'
actual_registry="$(git -C "$repository" show "$integration_commit:shared-ticket-registry.txt")"
[[ "$actual_registry" == "$expected_registry" ]] || {
	printf 'final wave repair lost registry entries: %s\n' "$actual_registry" >&2
	exit 1
}

ln -s "$repository" "$temporary_directory/repository-link"
set +e
(
	cd "$repository"
	CAMPAIGN_ID="symlink-confinement-$$" \
		WORKTREE_ROOT="$temporary_directory/repository-link/hidden-worktrees" \
		./scripts/local-ticket-loop/proposed-loop.sh --run
) >"$temporary_directory/symlink-stdout" 2>"$temporary_directory/symlink-stderr"
symlink_status=$?
set -e
[[ "$symlink_status" == 1 ]] || {
	printf 'expected symlinked in-repository WORKTREE_ROOT to be rejected\n' >&2
	exit 1
}
grep -Fq 'WORKTREE_ROOT resolves inside the repository' "$temporary_directory/symlink-stderr"
[[ ! -e "$repository/hidden-worktrees" ]]

# A loop that exits 0 without committing must fail the campaign and must not
# advance the integration branch.
no_change_repository="$temporary_directory/no-change-repository"
git clone -q "$repository" "$no_change_repository"
git -C "$no_change_repository" config user.name "Proposed Loop Test"
git -C "$no_change_repository" config user.email "proposed-loop-test@example.invalid"
git -C "$no_change_repository" checkout -q main
no_change_baseline="$(git -C "$no_change_repository" rev-parse HEAD)"
set +e
(
	cd "$no_change_repository"
	CAMPAIGN_ID="no-change-$$" \
	DEFAULT_BASE_BRANCH=main \
		MERGE_BACK_BRANCH=main \
		BARRIER_DIRECTORY="$temporary_directory/barriers-no-change" \
		WORKTREE_ROOT="$temporary_directory/no-change-worktrees" \
		NO_CHANGE_TICKET=02-walking-skeleton-run \
		TICKET_VERIFY_COMMAND=true \
		INTEGRATION_VERIFY_COMMAND=true \
		./scripts/local-ticket-loop/proposed-loop.sh --run
) >"$temporary_directory/no-change-stdout" 2>"$temporary_directory/no-change-stderr"
no_change_status=$?
set -e
[[ "$no_change_status" == 1 ]] || {
	cat "$temporary_directory/no-change-stderr" >&2
	printf 'expected a successful loop with no commit to be rejected\n' >&2
	exit 1
}
grep -Fq 'returned success without creating a commit' "$temporary_directory/no-change-stderr"
no_change_target="$(git -C "$no_change_repository" rev-parse --verify \
	"refs/heads/local-ticket-loop/no-change-$$/integration^{commit}")"
[[ "$no_change_target" == "$no_change_baseline" ]] || {
	printf 'no-change campaign advanced its integration branch\n' >&2
	exit 1
}

# An interrupted campaign must resume from its integration branch: waves that
# already integrated are skipped, ticket branches are adopted rather than
# rejected, and work left uncommitted is checkpointed so the loop can run.
resume_repository="$temporary_directory/resume-repository"
git clone -q "$repository" "$resume_repository"
git -C "$resume_repository" config user.name "Proposed Loop Test"
git -C "$resume_repository" config user.email "proposed-loop-test@example.invalid"
git -C "$resume_repository" checkout -q main
resume_campaign="resume-$$"
resume_worktrees="$temporary_directory/resume-worktrees"

set +e
(
	cd "$resume_repository"
	CAMPAIGN_ID="$resume_campaign" \
	DEFAULT_BASE_BRANCH=main \
		MERGE_BACK_BRANCH=main \
		BARRIER_DIRECTORY="$temporary_directory/barriers-resume-first" \
		WORKTREE_ROOT="$resume_worktrees" \
		INTEGRATION_REPAIR_COMMAND="$conflict_resolver" \
		FAIL_TICKET=08-anthropic-adapter \
		TICKET_VERIFY_COMMAND=true \
		INTEGRATION_VERIFY_COMMAND=true \
		./scripts/local-ticket-loop/proposed-loop.sh --run
) >"$temporary_directory/resume-first-stdout" 2>"$temporary_directory/resume-first-stderr"
resume_first_status=$?
set -e
[[ "$resume_first_status" == 1 ]] || {
	printf 'expected the seeded wave-3 failure to fail the campaign\n' >&2
	exit 1
}
grep -Fq 'wave 3 failed' "$temporary_directory/resume-first-stderr"

resume_branch="local-ticket-loop/$resume_campaign/integration"
interrupted_commit="$(git -C "$resume_repository" rev-parse --verify "refs/heads/$resume_branch^{commit}")"

# Wave 2 integrated before the failure, so the campaign has real progress to lose.
git -C "$resume_repository" cat-file -e "$interrupted_commit:implemented-02-walking-skeleton-run.txt" 2>/dev/null || {
	printf 'expected wave 2 to have integrated before the interruption\n' >&2
	exit 1
}
[[ -n "$(git -C "$resume_repository" status --porcelain \
	"$resume_worktrees/wave-3/08-anthropic-adapter" 2>/dev/null || true)" ]] ||
	[[ -f "$resume_worktrees/wave-3/08-anthropic-adapter/interrupted-08-anthropic-adapter.txt" ]] || {
	printf 'expected the failed ticket to leave uncommitted work behind\n' >&2
	exit 1
}

(
	cd "$resume_repository"
	BARRIER_DIRECTORY="$temporary_directory/barriers-resume-second" \
	MERGE_BACK_BRANCH=main \
		WORKTREE_ROOT="$resume_worktrees" \
		INTEGRATION_REPAIR_COMMAND="$conflict_resolver" \
		TICKET_VERIFY_COMMAND=true \
		INTEGRATION_VERIFY_COMMAND=true \
		./scripts/local-ticket-loop/proposed-loop.sh --resume "$resume_campaign"
) >"$temporary_directory/resume-stdout" 2>"$temporary_directory/resume-stderr" || {
	cat "$temporary_directory/resume-stderr" >&2
	printf 'resume run failed\n' >&2
	exit 1
}

grep -Fq 'Campaign complete.' "$temporary_directory/resume-stdout"
grep -Fq "resuming campaign $resume_campaign" "$temporary_directory/resume-stderr"

# Waves that already integrated must be skipped, not redone.
for skipped in 1 2; do
	grep -Fq "wave $skipped has no open tickets; skipping" "$temporary_directory/resume-stderr" || {
		printf 'resume did not skip wave %s\n' "$skipped" >&2
		exit 1
	}
done

# The three wave-3 tickets that had already committed must be adopted in place.
grep -Fq 'resuming ticket 03-search-document-evidence in place' "$temporary_directory/resume-stderr"
grep -Fq 'resuming ticket 07-exa-adapter in place' "$temporary_directory/resume-stderr"
grep -Fq 'checkpointed interrupted work for ticket 08-anthropic-adapter' \
	"$temporary_directory/resume-stderr" || {
	printf 'resume did not checkpoint the interrupted ticket\n' >&2
	exit 1
}

resumed_commit="$(git -C "$resume_repository" rev-parse --verify "refs/heads/$resume_branch^{commit}")"
git -C "$resume_repository" merge-base --is-ancestor "$interrupted_commit" "$resumed_commit" || {
	printf 'resume discarded the work the interrupted campaign had integrated\n' >&2
	exit 1
}
for ticket in "${tickets[@]}"; do
	[[ "$ticket" != 01-* ]] || continue
	git -C "$resume_repository" cat-file -e "$resumed_commit:implemented-$ticket.txt" 2>/dev/null || {
		printf 'resumed campaign lost the marker for ticket %s\n' "$ticket" >&2
		exit 1
	}
done

# Resuming a campaign that never existed must fail rather than silently start one.
set +e
(
	cd "$resume_repository"
	MERGE_BACK_BRANCH=main \
	./scripts/local-ticket-loop/proposed-loop.sh --resume "no-such-campaign-$$"
) >"$temporary_directory/resume-missing-stdout" 2>"$temporary_directory/resume-missing-stderr"
resume_missing_status=$?
set -e
[[ "$resume_missing_status" == 1 ]] || {
	printf 'expected resuming an unknown campaign to fail\n' >&2
	exit 1
}
grep -Fq 'no such campaign to resume' "$temporary_directory/resume-missing-stderr"

printf 'proposed-loop.sh: isolated parallel-wave integration test passed\n'
