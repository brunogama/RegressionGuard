Title: Text rule migration contract
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: 16-syntactic-evidence-model, 17-source-location-to-diff-line-mapping

## Question

What is the per-rule contract for moving the five source-text rule families onto syntactic evidence?

In scope: disabled_or_skipped_test, weakened_assertion, production_code_deletion, control_flow_deletion, unchecked_error_path. Charting settled the policy: precision upgrades keep their existing rule IDs and severities. This ticket fixes the concrete contract for each.

For every rule resolve: which detections move to the tree and which stay on lines, what the tree lets it catch that the string matcher missed (`weakened_assertion` currently matches a hardcoded list of exact spellings, so `XCTAssertTrue( true )`, `#expect(1 == 1)`, and `XCTAssertEqual(2, 2)` all pass today), whether the line-based path is retained as the degradation fallback, and what evidence the finding now carries.

## Resolution

The contract is one shape, applied five times. A migrating rule adopts `SyntaxAwareRule` and splits
its detections into three groups, and the split *is* the per-rule answer:

- `diffViolations` - the evidence is the diff itself, a tree would add nothing, so it always runs.
- `syntacticViolations` - reads the paired trees, and runs whenever both sides the change expects
  are parsed.
- `textFallbackViolations` - the same questions asked of source text, and runs only when the trees
  are not there.

Three groups rather than a whole-rule switch, because the interesting rules are mixed: a test file
deleted outright is a fact about the diff whether or not a parser ran, while the skip marker two
lines below it is a question about syntax. A two-way switch would have made the diff-level
detections ride on the tree's availability and vanish from a degraded run.

**The line path is retained, for every detection that has one.** A run reaches rules without a
parser in the ordinary course - a binary-distributed RegressionGuardKit, an unreachable base ref -
and `UnavailableSyntacticEvidenceProvider` is still the only provider that exists. Dropping the
text path would turn each of those runs into a silent pass, which is the one thing the evidence
model forbids. What the fallback may not do is pass itself off as the sharper answer.

**The finding says what it was judged on.** `Violation.evidence` is a `ViolationEvidence` with
three cases: `.diff`, `.syntax`, and `.degradedDiff` for a syntax-backed detection that had to run
on text. The dispatch sets it, not the rules, so a rule cannot forget. `.degradedDiff` is the
weaker claim and pairs with the `SyntaxEvidenceGap` the run already reports - together they say
both "this finding is at text precision" and "findings for this file may be missing entirely". A
file no rule requested is *not* degraded: nothing was expected, so nothing is missing.
Serialising the field into the report is deliberately left to Report version and compatibility;
`GuardFinding` does not carry it yet, so `GuardReport` stays at `schemaVersion: 1`.

Per rule:

**`disabled_or_skipped_test`** - two of four detections move. Skip markers become marker *nodes*
the change touched: a disabling trait inside an attribute, a `@Disabled` attribute, an `XCTSkip*`
call. That names the declaration that stopped running, sees a trait spread over several lines and
a whole `@Suite(.disabled)`, and stops matching markers written in comments, in string payloads,
or in a test's own name - the last of which the line path has to work around by editing the
declared identifier out of the line before matching it. The marker's *own* span is what must be
touched, not the declaration around it, so a test that was already disabled stays out of the
report when its body is edited. Test-function identity compares `functionDecl` nodes on the two
trees instead of scanning for `func ` and guessing at a nearby `@Test` within five lines, and
drops the rule's two per-file `git show` calls. Staying on the diff: a deleted test file, and a
test commented out in place, which is a comparison between an added comment and the removed line
it repeats.

**`weakened_assertion`** - all three detections move. A tautology stops being a list of exact
spellings and becomes a property of the call's arguments: an assertion given only constants cannot
depend on the code under test. `XCTAssertTrue( true )`, `#expect(1 == 1)` and `XCTAssertEqual(2, 2)`
are caught, `XCTAssertEqual(sut.total, 42)` stays healthy, and `XCTFail("…")` is exempt because a
literal message is the correct way to write it. A net removal counts assertion *calls* over the
whole file on each side rather than lines carrying an assertion prefix, so a multi-line assertion
counts once and an assertion moved between functions is not reported as deleted. A deleted file is
that same count against zero, off the base tree, which also drops a `git show`.

**`behavior_deletion`** (control_flow_deletion) - the whole rule moves. "Control-flow lines
removed" becomes "branches the file no longer has", counted as nodes: one `if` written over four
lines counts once, a `return` inside a string literal and a variable named `catchphrase` stop
counting at all, and the `added.isEmpty` guard that a single unrelated added `return` was enough
to defeat becomes the difference between the two counts. The count is over the whole file, since a
deleted branch is by definition not in head to be counted there; the diff still decides whether
anything was removed at all and where the finding lands.

**`error_handling_collapse`** (unchecked_error_path) - both detections move. A force-unwrap
becomes a `forceUnwrapExpr` the change touched, instead of a regular expression already carrying
three carve-outs and still matching a `!` inside a string. A swallowed `catch` becomes a
`catchClause` whose body holds nothing, which catches a multi-line empty catch and one holding
only a comment, and carries a line - the text path matches across the added lines joined together
and can produce none. The force-unwrap family listed as an AST-only candidate on the rule catalog
belongs here, not under a new rule ID: `error_handling_collapse` already owns it.

**`production_code_deletion`** is a facade over the two rules above. It declares the need on their
behalf and forwards the whole bundle, so a caller running only the facade is not silently handed
the degraded answer.

No obligation is recorded on the parsing target. Where one could have been written down instead
of handled, it is handled - an obligation that fails silently is worth less than code the choice
cannot break. swift-syntax
makes a call's callee a child of the call, so a faithful projection would put `XCTAssertTrue` in
the subtree as a `declReferenceExpr` - a run-time value, which would make every assertion look
like it could fail and switch the whole tautology detection off without a single test going red.
The callee is dropped explicitly, whether or not the projector also hoists it into the node's
name, and both projection shapes are pinned by tests. A macro's `#` is treated the same way.

Attributes are the same problem twice more. `SyntaxNode.attributes` is the documented carrier and
an `attribute` child node is what a faithful projection gives; the skip markers read only the
nodes and test-function identity read only the array, so each was one projection choice away from
finding nothing - `@Disabled` unseen, or every `@Test` function reading as an ordinary one and the
renames excused. Both shapes are now read through `carriesAttribute(named:)`. A marker with a node
of its own anchors to it; one legible only as a string anchors to the declaration, where only a
change to its own lines counts, so a body edit under an already-disabled test still reports
nothing.

The fixtures had to be split to prove any of this: a fixture that fills both shapes cannot tell a
one-shape reader from a two-shape one, and the node-shape test passed against an array-only reader
until it was pointed at a node-only fixture.

Every finding anchors to a node the change actually touched, with no fallback to one it did not.
Where the count says something was removed but no removed line names it, the rule reports nothing
rather than pointing a reader at code the author never wrote - the failure ticket 17 exists to
prevent. A deleted file has no head line to land on and reports none, which `Violation.line` is
optional for.

Two limits are left standing. Whole-file counting means code moved between two files reads as a
deletion in one of them, exactly as the line path already behaved. And an empty `catch` is only
claimed when a `codeBlock` body was actually projected: an unrecognised projection is not evidence
that the error is discarded.

## Implementation

- `Sources/RegressionGuardKit/ViolationEvidence.swift` and `Violation.evidence` / `judged(on:)`.
- `Sources/RegressionGuardKit/Rules/SyntaxAwareRule.swift`: the three-group protocol, the
  `requiresSyntacticEvidence` default, and the dispatch that marks degraded findings.
- Detection vocabulary in `Sources/RegressionGuardKit/Syntax/`: `AssertionCall`, `TestSkipMarker`,
  `ControlFlowNode`, plus `SyntaxNode+Queries` (`nodes(named:)`, `nodes(ofAnyKind:)`,
  `innermostNode(ofKind:containing:)`, `LineSpan.contains(_:)`). Four node kinds added:
  `floatLiteralExpr`, `nilLiteralExpr`, `infixOperatorExpr`, `repeatStmt`.
- `+Syntax.swift` extensions for all four concrete rules, plus `TestFunctionIdentity+Syntax`.
  `ProductionCodeDeletionRule.swift` was split so `ControlFlowDeletionRule` and
  `UncheckedErrorPathRule` each own a file, per the one-type-per-file convention. The
  production-path predicate both rules answered privately and identically moved onto
  `RuleContext.isProductionPath(_:)`.
- 44 tests added across `SyntaxAwareRuleTests`, `WeakenedAssertionRuleSyntaxTests`,
  `DisabledOrSkippedTestRuleSyntaxTests`, `ProductionShortcutRuleSyntaxTests`, with fixtures in
  `SyntaxFixture`. The existing line-based rule tests are kept unchanged: they are now the
  degradation path's coverage, which is the reason to keep them rather than migrate them. Real
  parsed fixtures remain Syntactic test fixture strategy's question.

Found and fixed while wiring this up:

- `regression-guard check` named every file on stderr when the *only* reason was
  `parserUnavailable`, which is a single global condition - a run over this branch printed 32
  identical lines under a header that already carried the count. A run with no parser now prints
  the header and one line saying so; every other reason stays per file.
- `SyntacticEvidenceEngineTests` asserted that a default-rule-set run reports no evidence gaps.
  That was true only while no rule asked for a tree. It now asserts the gap is reported, which is
  the behaviour the evidence model requires.

## Amendment

The AST-only rule catalog resolved two of its candidates into `error_handling_collapse`, so this
contract owns them rather than a new rule ID. Both keep the family's existing `warning` severity,
since a precision upgrade to an existing ID does not change what it reports at.

**A `guard` body reduced to a bare `return`.** A failure path that used to throw, trap, or log now
exits silently, which is this family's subject exactly. Built, and base-relative rather than
absolute: `guard let x else { return }` is ordinary Swift, so flagging every `guardStmt` whose
body holds only a valueless `returnStmt` would bury the rule under idiom. Only a guard whose base
counterpart did more counts, and guards are matched between the trees by their condition, since
position moves and nothing else identifies them. A newly written guard is therefore never
flagged.

**`try?` swallowing a previously-handled error.** Same subject, same remediation. Built, and
reported on introduction rather than base-relatively - the same shape as the force-unwrap
detection beside it, because writing a `try?` is itself the act being flagged.

This one could not be absorbed the way every other projection choice was. `SyntaxNodeKind` has a
single `tryExpr` and nothing else can separate `try` from `try?` or `try!`, so the spelling is
read off the node's `name` and that is now a documented obligation on the projector, recorded on
the kind itself. A projector that leaves `tryExpr.name` nil switches this detection off silently.
It is the second such obligation in the map, alongside a boolean literal's spelling in
`unreachable_assertion`, and both are for the same reason: the projection has one kind where the
language has several spellings.
