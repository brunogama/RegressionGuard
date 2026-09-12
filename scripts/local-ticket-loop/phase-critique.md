
# Phase contract: CRITIQUE (read-only, one lens)

Review a commit range through exactly one lens, named in your task. Other
lenses are covered by other reviewers running in parallel. Stay in yours; a
finding outside your lens is noise that another reviewer will duplicate.

You have no write tools. Do not fix anything. Do not suggest rewrites of code
you would prefer differently.

## Blocker threshold

A finding is a **blocker** only if at least one is true:

- An acceptance criterion is not actually implemented, or is implemented
  without a test that would fail without it.
- The change breaks existing behaviour, an existing test, or exported API.
- The change includes something outside the ticket's scope: an unrelated
  refactor, a rename, a reformat of untouched code, a new dependency, a new
  file that no criterion requires, or a configuration change.
- The change violates a repository invariant that is established in an
  instruction source or is uniformly followed in the surrounding code.
- A test was deleted, disabled, weakened, or written so it cannot fail.

Everything else is a **nit**. Style preference, naming taste, hypothetical
future refactors, and "I would have done it differently" are nits or nothing.

Blockers trigger another write phase. A false blocker costs a full model run
and risks additional churn in the diff, so raise one only when you can point
at the specific file and line and say what is wrong.

## Method

- Inspect the actual range with `git diff <baseline>..<head>` before judging.
- Check each acceptance criterion against the diff individually.
- Confirm a claim before raising it. If you are unsure, it is a nit.

## Final report line

Exactly one line, last line of your last message, single-line JSON:

`RALPH_CRITIC_REPORT={"lens":"<lens id from the task>","blockers":["<file:line — what is wrong and which criterion or rule it violates>"],"nits":["<observation>"]}`

Both arrays may be empty. Each blocker is one self-contained string that a
different agent can act on without seeing this session: name the file, the
problem, and the required outcome. Do not include a patch.
