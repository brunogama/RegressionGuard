# Local ticket loop

Runs local Markdown tickets in `.scratch/tickets` through an agent, either one at a time or in dependency-gated parallel waves.

Two entry points:

| Script | Transport | Concurrency |
| --- | --- | --- |
| `loop-claude.sh` | Claude Code (`claude -p`) | One ticket at a time, in the current checkout |
| `loop.sh` | Pi RPC | One ticket at a time, in the current checkout |
| `proposed-loop.sh` | delegates to `loop.sh` | One isolated worktree per ticket, waves in parallel |

## Sequential

```sh
# Inspect local state without running an agent
scripts/local-ticket-loop/loop-claude.sh --list

# Run one ticket
scripts/local-ticket-loop/loop-claude.sh 01-fidelity-layer

# Run an inclusive filename-ordered range
START_AT_TICKET=02-walking-skeleton-run STOP_AFTER_TICKET=05-cited-answer \
  scripts/local-ticket-loop/loop-claude.sh
```

The loop requires a clean Git worktree. For each unfinished ticket it:

1. sends the complete local Markdown ticket to the agent;
2. requires the agent to carry the ticket out through the `/implement` skill, which works
   test-first through `/tdd` and closes with `/code-review`;
3. requires a committed implementation and a structured completion report;
4. runs `swift build --build-tests && swift test` by default;
5. checks every acceptance criterion in the ticket;
6. commits the ticket checkbox update separately.

`/git-worktree`, `/implement`, `/tdd`, and `/code-review` live in `.agents/skills/` and are exposed to Claude Code, Codex, and Pi through symlinks in `.claude/skills/`, `.codex/skills/`, and `.pi/skills/`. Removing a symlink silently turns its `/name` line in the prompt into inert prose rather than a skill invocation.

Override verification with `RALPH_VERIFY_COMMAND`. Set `CLAUDE_RUN_OKF=1` to append the
`/okf` bundle stage. Run artifacts are stored under `.git/local-ticket-loop/`, so they never
dirty the worktree.

## Parallel waves

`proposed-loop.sh` runs `loop.sh` for each ticket, giving every ticket its own linked Git
worktree and branch so that independent tickets execute at the same time.

```sh
# Print the schedule without changing repository state
scripts/local-ticket-loop/proposed-loop.sh --plan

# Run the campaign
scripts/local-ticket-loop/proposed-loop.sh --run

# Continue a campaign that was interrupted
scripts/local-ticket-loop/proposed-loop.sh --resume <campaign-id>
```

The waves are computed from the `Blocked by:` edges in the ticket files: a ticket sits in the wave after the latest wave holding one of its blockers. Use full ticket IDs or unambiguous numeric prefixes, for example `Blocked by: 01, 03-search`. `Blocked by: none` or an omitted blocker line puts the ticket in the first wave.
After a wave finishes, each ticket tip is merged one at a time into a detached integration
worktree. A conflict is handed to `INTEGRATION_REPAIR_COMMAND` when one is configured;
otherwise the campaign stops with the conflicted worktree retained. The merged tree must pass
`INTEGRATION_VERIFY_COMMAND` before the campaign's integration branch advances and the next
wave starts from it.

After all waves pass, `proposed-loop.sh` merges the integration result back to `MERGE_BACK_BRANCH`
(default `feat/debtmap`). Successful ticket branches and the integration branch are kept for
audit; failed worktrees are kept for diagnosis.

### Resuming an interrupted campaign

A campaign that is killed mid-flight leaves its integration branch, its ticket branches, and
its worktrees behind. Starting a fresh campaign would take its baseline from `HEAD` and so
redo every wave the dead campaign had already integrated. `--resume <campaign-id>` takes the
campaign's integration branch as the baseline instead, which is what makes those waves skip:
each is already recorded as complete there.

Inside the wave that was interrupted, each ticket is treated on its own evidence:

- a ticket branch that does not exist yet starts fresh from the baseline;
- a ticket branch that exists is adopted in its own worktree, and its own commits become the
  baseline the agent continues from, so it finishes rather than restarts;
- work an interrupted agent left uncommitted is committed first as a `wip(...)` checkpoint,
  because the per-ticket loop requires a clean worktree and would otherwise refuse to run.
  The checkpoint message says the work is unreviewed, so the history does not present it as
  finished. Uncommitted changes to a protected path stop the resume instead of being
  committed.

`--resume` does not update the harness inside an existing ticket worktree. When the
interruption was caused by the harness itself, commit the fix on the base branch and merge it
into each ticket branch before resuming, so the fix sits below the baseline where the
protected-path check does not look.
Preconditions: the checkout must be clean and `BASE_REVISION` (default `feat/debtmap`) must
already contain the ticket files and this harness, so the tickets have to be committed before
the first campaign.

## Regression checks

```sh
scripts/local-ticket-loop/test.sh              # loop.sh
scripts/local-ticket-loop/test-proposed-loop.sh # proposed-loop.sh
```

`test-proposed-loop.sh` builds a throwaway repository with the real ticket filenames and a
fake per-ticket loop, then asserts parallel execution inside a wave, sequential merge
integration, conflict repair, `WORKTREE_ROOT` confinement, and rejection of a loop that
reports success without committing.
