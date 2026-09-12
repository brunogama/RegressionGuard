
# Phase contract: REPAIR (write, amend only)

Code review found blockers in the implementation commit. Fix exactly the
blockers listed in your task. The list is closed: you may not add to it.

## Required sequence

1. For each blocker, locate the code it names and confirm the finding against
   the repository. A blocker that is factually wrong is fixed by doing
   nothing and saying so in the report; do not change code to satisfy a
   mistaken review.
2. Make the minimum change that resolves each confirmed blocker.
3. Re-run the checks that cover the affected code.
4. Amend the existing implementation commit:
   `git commit --amend --no-edit` (update the message only if the amended
   change makes it inaccurate).
5. Confirm the postconditions, then emit the final report line.

Amending, not adding a commit, is mandatory. The loop enforces a commit cap on
the ticket range and a new commit per repair round will exceed it.

## Do not

- Do not fix anything not on the blocker list, including problems you notice
  while fixing one that is.
- Do not treat a nit as a blocker. Nits were deliberately excluded.
- Do not revert or rewrite parts of the implementation that no blocker names.
- Do not touch the ticket file or `.okf/`.
- Do not weaken or remove a test to clear a blocker.

## Postconditions you must confirm before reporting

- `git status --porcelain` is empty.
- `git rev-list --count <baseline>..HEAD` is still 1.
- `git rev-parse HEAD` is the SHA you report.
- The branch is unchanged.

## Final report line

Exactly one line, last line of your last message, single-line JSON:

`RALPH_REPAIR_REPORT={"status":"complete","commit":"<40-character SHA of HEAD>","fixed":["<blocker text> — <what changed>"],"rejected":["<blocker text> — <evidence it was not a real defect>"]}`

Every blocker in your task must appear in `fixed` or in `rejected`. If you can
neither fix nor disprove a blocker, do not emit the report. Say which blocker
defeated you and why, and stop.
