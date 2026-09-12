
# Phase contract: IMPLEMENT (write, one commit)

Implement every unchecked acceptance criterion in the ticket you were given.
Nothing else in the repository is in scope.

## Required sequence

1. Count the acceptance criteria in the ticket text. Count checkbox lines at
   any indentation: `total` is every `[ ]` and `[x]`, `open` is every `[ ]`.
   You will report both numbers and the loop compares them with its own count.
   A mismatch fails the ticket, so count before you code.
2. Verify the context pack against the repository for anything you will rely
   on. It was gathered by another agent and may be stale or wrong.
3. Work test-first where the criterion is testable: add or extend a test that
   fails for the right reason, then make it pass.
4. Run the narrowest checks that exercise your change, then the repository's
   checks for the area you touched.
5. Review your own diff hunk by hunk. For each hunk, name the criterion it
   serves. Revert any hunk you cannot attribute.
6. Create exactly one commit containing the whole change. Do not commit in
   stages. Follow the repository's commit message convention.
7. Confirm the postconditions, then emit the final report line.

## Postconditions you must confirm before reporting

- `git status --porcelain` is empty.
- `git rev-list --count <baseline>..HEAD` is 1.
- `git diff --name-only <baseline>..HEAD` matches the file list you report,
  exactly, with no extra and no missing entry.
- `git rev-parse HEAD` is the SHA you report.
- The branch is unchanged.

## Do not

- Do not edit the ticket file or tick its checkboxes. The loop owns completion
  tracking.
- Do not create a second commit for tests, formatting, docs, or cleanup.
- Do not amend or rewrite anything that existed before your commit.
- Do not touch `.okf/`. A later phase owns that bundle.
- Do not run the loop's verification command as a substitute for the checks
  above; the loop runs it independently regardless.

## Final report line

Exactly one line, last line of your last message, single-line JSON:

`RALPH_COMPLETION_REPORT={"status":"complete","ticket":"<id>","criteria_total":<int>,"criteria_open":<int>,"criteria_satisfied":<int>,"files_changed":["<path>",...],"implementation":{"status":"complete","summary":"<what changed>"},"verification":{"status":"complete","summary":"<checks actually run and their results>"},"code_review":{"status":"complete","summary":"<self-review outcome>"},"commit":"<40-character SHA of HEAD>"}`

`files_changed` is repository-relative paths, exactly as `git diff --name-only`
prints them.

`criteria_satisfied` must equal `criteria_open`. If it does not, do not emit
the report at all. State which criteria remain and why, in plain prose, and
stop.
