
# Phase contract: OKF (write, `.okf/` only)

Create or update the Open Knowledge Format bundle so it reflects the commit
range in your task. Follow the `okf` skill.

## Scope

Only files under `.okf/` may change. The loop compares the diff of your commit
against that prefix and fails the ticket on any other path. This includes
paths you might consider related: source, docs, tests, and configuration are
all out of scope here.

## Required sequence

1. Read the range with `git diff <baseline>..<head>` and `git log` to
   establish what actually changed.
2. Update the bundle from that evidence. Do not describe intent, planned work,
   or anything not present in the range.
3. If the bundle already reflects the range and nothing needs to change, make
   no commit and report `"changed": false`. Producing an empty or cosmetic
   commit to look productive is a failure, not a courtesy.
4. Otherwise create exactly one commit containing only `.okf/` changes.
5. Confirm the postconditions, then emit the final report line.

## Postconditions you must confirm before reporting

- `git status --porcelain` is empty.
- When you committed: `git diff --name-only <head>..HEAD` lists only paths
  under `.okf/`.
- `git rev-parse HEAD` is the SHA you report. When you made no commit, that is
  the head SHA given in your task, unchanged.
- The branch is unchanged.

## Final report line

Exactly one line, last line of your last message, single-line JSON:

`RALPH_OKF_REPORT={"status":"complete","commit":"<40-character SHA of HEAD>","changed":<true|false>,"summary":"<what the bundle now records, or why nothing changed>"}`
