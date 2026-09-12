Title: AST-only rule catalog
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: 16-syntactic-evidence-model

## Question

What are the rule identities, severities, and detection shapes for the rule families a parser newly makes possible?

Charting settled that all candidates are in scope, and that new rule IDs ship advisory by default under the existing calibration path. The candidates surfaced so far: a test function silently renamed off the `test` prefix; `XCTSkip` or `withKnownIssue` introduced; an assertion moved inside a branch that can never execute; a function body replaced by `fatalError` or a stub return; `try?` swallowing a previously-handled error; a force-unwrap replacing real error handling; a `guard` body reduced to a bare `return`; access level widened to bypass `@testable`.

For each, resolve whether it is genuinely distinct from an existing family or a precision upgrade wearing a new name, its stable rule ID, its evidence and confidence, and the benign maintenance patterns it must not flag. Families that collapse into an existing rule ID belong in the text rule migration contract instead.

## Resolution

Eight candidates in, three new rule IDs out. Five collapse or are rejected, which is the more
useful half of the answer: a catalog that minted eight IDs would have split single harms across
several families and made every one of them a configuration line a guarded repository has to
learn.

The test for distinctness used throughout is not "is the syntax different" but "does a reviewer
do something different about it, and would folding it in change a severity". A detection that
shares a remediation with an existing family is a precision upgrade to that family, however
different its detection shape.

### New rule IDs

**`known_issue_suppression`** (advisory, `warning`). A `withKnownIssue` call the change
introduced. Distinct from `disabled_or_skipped_test` because a suppression is not a skip: the
test runs, its assertions run, and the resulting failure is absorbed and reported as expected.
The remediation differs too - a skip is fixed by restoring execution, a suppression by fixing the
issue or justifying it. The deciding argument is severity. Folding it into
`disabled_or_skipped_test` would hand it that family's blocking severity on day one, and
suppressing a genuinely known upstream failure is ordinary reviewable practice. Evidence is the
call node's own lines, so editing an assertion under a suppression that was already there is not
this change's doing. Must not flag: a pre-existing suppression whose body is edited, a helper
merely named `withKnownIssueTracker`, anything outside a test path.

**`implementation_stubbed`** (advisory, `warning`). A function whose body was real and is now a
single trap or a single constant return. Distinct from `behavior_deletion`, which counts the
branches a file lost: stubbing can leave that count unchanged or raise it, and one named function
that no longer computes anything is a sharper claim than a count. The signature survives, so
callers still compile and the type checker says nothing. Requires both trees, because a stub is
only a regression relative to what was there before. Must not flag: a newly added function that
traps, which is an honest unimplemented requirement and of which `required init?(coder:)` is the
archetype; a function that already trapped; a return that still names a computed value; an
overload set where one member was always a trap. Test paths are excluded - a stubbed test is
`disabled_or_skipped_test`'s business.

**`unreachable_assertion`** (advisory, `warning`). An assertion the change put where it cannot
run. The same harm `weakened_assertion` catches, reached differently, and separate from it for a
reason that is about confidence rather than shape: `weakened_assertion` decides a question about
a call's own arguments and blocks on the answer, while reachability is undecidable from syntax.
A heuristic inheriting a blocking severity is how a guard earns the right to be switched off
wholesale. Only two cases are claimed, both provable without semantics: an assertion under a
literal `if false`, and one after an unconditional exit in the same block. Deliberately not
claimed: a condition constant only after inlining, a loop that never iterates, an `#if` branch
excluded by build flags. Must not flag: an assertion before the exit, an assertion under an
ordinary condition, a non-assertion call after a return, a region the change never touched.

### Collapsed into existing families

**A test function renamed off the `test` prefix** is `disabled_or_skipped_test`, and is already
built: `TestFunctionIdentity` reports a base test function that survives with its test identity
lost, moved onto `functionDecl` comparison by the text rule migration contract. Not a new family
- the harm and the remediation are identical to a disabled test.

**`XCTSkip` introduced** is `disabled_or_skipped_test`, already built as a skip-call marker
matched by prefix, which covers `XCTSkipIf` and `XCTSkipUnless` too. Only the `withKnownIssue`
half of this candidate is new, and it is split out above.

**A force-unwrap replacing real error handling** is `error_handling_collapse`. Already settled by
the text rule migration contract, which said so explicitly; recorded here so the catalog does not
read as though it were still open.

**`try?` swallowing a previously-handled error** is `error_handling_collapse`. The error path
stopped being handled, which is precisely that family's subject, and the remediation is the same.
Not implemented, and the reason is a projection limit rather than a decision: `SyntaxNodeKind` has
a single `tryExpr` and nothing distinguishes `try` from `try?` or `try!`. The rule cannot be
written until the projection carries the spelling. Recorded as an amendment on the text rule
migration contract, which owns that family.

**A `guard` body reduced to a bare `return`** is `error_handling_collapse`, for the same reason:
a failure path that used to throw, trap, or log now exits silently. This one is expressible on
today's projection - a `guardStmt` whose body block holds only a `returnStmt` with no value - and
is recorded on the same amendment as work that family can take.

### Rejected

**Access level widened to bypass `@testable`** is not a shortcut regression and gets no rule ID.
`CONTEXT.md` defines the subject as a change that "removes, weakens, hides, or bypasses evidence
of required software behavior". Widening `internal` to `public` so a test can reach a symbol
weakens encapsulation, not evidence: the test still runs, still asserts, and still fails when the
behaviour breaks. It is a real API-design concern and belongs to a linter or to review, not to
this guard. Admitting it would widen the guard's subject from evidence to design, and the next
candidate through that door is harder to refuse than this one.

### Severity and adoption

All three ship advisory, as charting settled for new rule IDs, and none of them appears in any
existing configuration. Promotion to blocking runs through the observer's calibration path once
per-rule false-positive rates exist, which is the map's open item and not this ticket's to take.

The three are registered in `RuleEngine.defaultRules` and are AST-only: no text fallback, because
approximating any of them on added lines would fire on the words in their own doc comments. A run
without a parser therefore contributes nothing from them and reports the missing evidence as a
gap, which is the arrangement the syntactic evidence model already settled.
