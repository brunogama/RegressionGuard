Title: Syntactic test fixture strategy
Labels: wayfinder:prototype
Status: closed
Assignee: none
Parent: Swift-syntax syntactic evidence map
Blocked by: 16-syntactic-evidence-model

## Question

What should a rule test look like once rules consume parsed source?

`TestSupport.fileDiff(path:removed:added:)` hand-builds a diff from parallel string arrays today, synthesizing line numbers and never exercising a parser. Rules that read trees cannot be tested that way, and the fixtures are where the improved tests in this effort actually land.

Prototype a fixture pair and one migrated rule test to react to, then resolve: whether fixtures are real Swift files on disk at base and head or inline source strings parsed in the test; how a test expresses "this file changed this way" without hand-writing hunks; whether the existing line-based tests are kept to cover the degradation path; and what keeps fixtures readable as the rule catalog grows.

## Resolution

Two layers, not one. The hand-built fixtures stay, and a second suite holds them to what the parser
actually emits.

That split is forced rather than preferred. RegressionGuardKit has no dependencies and its test
target cannot be given a parser, so a rule test in the root package can only state the tree it
wants. Those tests are worth keeping - they say the edge case outright, they run in milliseconds,
and they are where a rule's reasoning is pinned. What they cannot do is notice that the shape they
assume is not the shape swift-syntax produces, and the prototype proved that is not a theoretical
risk: three of the four tree-reading families were reporting nothing at all against real source
while every fixture passed.

`RegressionGuardCLI/Tests/RegressionGuardSyntaxTests/ParsedFixtureRuleTests.swift` is the second
layer. It lives in the CLI package because that is where the parser is.

### What a parsed fixture is

A `SourcePair`: one path, two whole versions of the file. The test writes the base version into a
scratch repository and commits it, writes the head version and commits that, then runs
`RegressionGuardRunner` with a provider that reads each side back out of git at its ref and projects
it with `SwiftSyntaxProjection`. Real diff, real trees, real engine.

Answering the ticket's four questions:

- **On disk or inline?** Inline source, round-tripped through git. Checked-in fixture files cannot
  express a pair - a file at a path has one content - and the repository's own guard would read a
  `Tests/` fixture as a test. The realism that matters is not where the text is authored but that
  the tree comes from a parser and the diff comes from `git`.
- **How does a test say "this file changed this way"?** By stating both versions and letting `git`
  compute the difference. No hunks are written by hand, which also fixes a quieter problem:
  `TestSupport.fileDiff` synthesizes line numbers from 1, so a rule reporting the wrong line still
  passes there. Here the fixture's line 5 is the file's line 5, and the tautology test asserts it.
- **Are the line-based tests kept?** Yes, and the degradation path gets a case of its own. The same
  pair run with no provider is missed by the text matchers - `XCTAssertEqual(42, 42)` is not one of
  the five spellings they know - and the run reports `parserUnavailable` gaps on both sides rather
  than reading clean. That is the promise of the evidence model asserted end to end for the first
  time.
- **What keeps it readable?** A fixture is the source a reviewer would see, and each AST-only family
  contributes one `RuleExpectation` to a parameterised case. Adding a family is adding a pair.

### What the prototype found

Three defects, none of which any existing test could have caught:

1. **`functionCallExpr` was projected unnamed.** `AssertionCall` recognises an assertion by the name
   on the call, so every `XCTAssert...` in a real file read as a non-assertion and the whole
   `weakened_assertion` tree path was silent. `SyntaxNodeName` now names a call after its callee.
2. **The projector's own test hid it.** `namesCallee` is titled "names a call's callee on the call
   rather than only on a child" and asserted the child's name. It passed while the thing it is named
   for was false.
3. **`SyntaxNode.statements` unwrapped `codeBlockItemList` but not `codeBlockItem`.** swift-syntax
   uses both, so every body read as a single opaque statement: `implementation_stubbed` and
   `unreachable_assertion` reported nothing on any real file. Both wrappers are unwrapped now, and
   the root package carries a fixture for the real two-layer shape beside the list-only one it
   already had.

The fourth family, `known_issue_suppression`, fired correctly - which is the reason to run all of
them rather than one and generalise.

A fixture written as source can also be wrong in a way a hand-built tree cannot. The first stranded
assertion fixture put `return` on its own line above the assertion; SwiftParser reads those two
lines as one `return XCTAssertEqual(...)`, so the rule was right to find nothing. The hand-built
version would have accepted the intended reading and pinned a behaviour Swift does not have. That
cuts both ways and is an argument for this layer, not against it.

### What this does not do

It does not migrate the existing rule suites. They stay where they are and keep their shape; this
adds the layer that tells them when they are describing a tree that never occurs. Migrating a
family's whole suite to parsed fixtures would cost the edge cases that are only expressible by
construction - a degraded side, a projector that emits one shape rather than another - and those are
exactly what the hand-built fixtures are for.

## Amendment: the sweep covers every tree-reading family

The prototype ran four families and this now runs all six: `disabled_or_skipped_test`,
`behavior_deletion` and `error_handling_collapse` joined the parameterised case once the shipping
provider landed and there was a real run to point them at.

All three fire on parsed source, and each case asserts `.syntax` rather than only that something was
reported. That distinction is what makes the sweep meaningful for the families that do have a text
fallback: unlike the AST-only three, a projection they cannot read does not leave them silent - it
drops them back to the matchers the tree was supposed to replace, which reports something and looks
like a pass.

The three needed no fixes, which is the useful negative result: the defects the prototype found were
projection shapes, and once `functionCallExpr` carried its callee and `statements` unwrapped both
wrappers, the families that depend on those shapes - `XCTSkip` recognised as a call, a block's
statements counted as statements - were correct as written.
