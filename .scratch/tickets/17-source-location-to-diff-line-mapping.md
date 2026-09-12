Title: Source location to diff line mapping
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: 16-syntactic-evidence-model

## Question

How does a finding on a syntax node become a finding on a changed line?

Violations today carry a diff-local line number taken straight from the added line that matched. A syntax node carries an absolute position in the whole head file, most of which the change never touched. Without a mapping, AST rules will report findings against pre-existing code that the author did not write, which is the fastest way to lose trust in the tool.

Resolve how node positions are converted to line numbers, how a rule decides whether a node falls inside the change rather than merely inside the file, and what happens for constructs that straddle the boundary: a function whose signature is untouched but whose body changed, or a node deleted at base with no head position at all.

Two traps named by Swift-syntax capability research. Report `SourceLocation.line` and never `presumedLine`, because a `#sourceLocation` directive would otherwise yield line numbers that do not exist in the diff. And sweep all four comment trivia cases (`lineComment`, `blockComment`, `docLineComment`, `docBlockComment`) on both leading and trailing trivia, since upstream leaves attachment undocumented and approval markers ride in comments.

## Resolution

A node position becomes a finding through one Kit-native value, `ChangedLineMap`, built from the
`FileDiff` a rule already holds. It carries the lines the change touched on each side, in that
side's own numbering, and the translation from a base line to the head line a reader opens. Nothing
new enters the evidence bundle: the map is derived, so it cannot disagree with the diff it came
from, and a rule that wants it writes `fileDiff.changedLines`.

A node is in the change when a changed line falls inside its span on its own side, never merely
because it is in the file. `touches(_:at:)` answers that, `changedNodes(ofKind:in:at:)` applies it
to a whole tree, and `changedLines(in:at:)` gives back the lines that qualified. The side is
explicit in every call, reusing `SyntaxRef`, because asking a head tree's span against base line
numbers is the exact mistake this ticket exists to prevent.

Straddling constructs are answered with a three-case `NodeChangeScope` rather than a boolean.
`own` means the change landed on the node's own lines, `nested` means it landed only below them -
a body edited under an untouched signature - and `outside` means the change never reached the
node. A node's own lines are its span less the interior of every child, keeping each child's first
line: a body's opening brace usually sits on the signature line, and subtracting whole child spans
would leave a single-line signature owning nothing. The cost is that an edit to a lone `{` line
reads as `own`, which is a formatting-only case and errs toward attributing the change to the
declaration rather than hiding it.

A node with no head position at all is reported through the translation, not with a base number
dressed up as a head one. `headLine(forBaseLine:)` maps a surviving line to wherever the change
moved it, and a deleted line to the head line its deletion left behind, which is the place a
reader can see the code went missing. Lines no hunk names are shifted by the net delta of the
hunks before them, so the mapping covers the whole file rather than only the hunks. A file deleted
outright has no head side, and the honest answer is `nil`: `Violation.line` is already optional.
`reportLine(for:at:)` is what a rule calls - the first changed line inside the span, so a finding
on a large node points at the edit rather than at the declaration enclosing it, translated when
the span came from base.

Both traps are recorded as obligations on the parsing target, which is the most this ticket can
do: nothing here can enforce them, because the projector that would violate them does not exist
yet. `LineSpan` and `ChangedLineMap` are documented as physical lines only, with the requirement
to report `SourceLocation.line` rather than `presumedLine` written where the parsing target will
read it - a `#sourceLocation` directive could otherwise name a line absent from the diff. On
trivia, `SyntaxNode.comments` names all four comment cases (`lineComment`, `blockComment`,
`docLineComment`, `docBlockComment`) on leading and trailing trivia both, and comments are read
through a sweep - `allComments`, `hasComment(containing:)` - rather than off a single node,
because upstream leaves attachment undocumented and an approval marker can land on either side of
the node it authorizes. Comments carry no line of their own in the projection, so a marker is
scoped to a node's span, not to a line; finer scoping would need the projection to line-number
trivia, which no in-scope rule needs.

Two limits are left standing deliberately. `changedNodes(ofKind:in:at:)` cannot check that `ref`
names the side its tree came from, because `SyntaxTree.ref` is the free-form ref a tree was read
at rather than which side of the comparison it is; the precondition is documented, and fixing it
by type belongs to the projection's ref modelling, not here. And `ownLines` works off spans alone,
so besides the lone-brace case above, a multi-line signature whose later lines are projected as a
child loses them to that child. Both depend on the projection shape that the text rule migration
contract settles.

## Implementation

- `Sources/RegressionGuardKit/Syntax/ChangedLineMap.swift`: `NodeChangeScope`, `ChangedLineMap`,
  `FileDiff.changedLines`.
- `SyntaxNode.ownLines` and `hasComment(containing:)`, `SyntaxTree.hasComment(containing:)`, plus
  the four-trivia-case contract on `SyntaxNode.comments`.
- 20 tests in `ChangedLineMapTests`, 4 added to `SyntaxTreeTests`. `ChangedLineMapTests`
  exercises the base-to-head arithmetic against real `GitDiffParser` output for a two-hunk diff
  and for a deletion running to the end of the file, where the anchor is clamped to the last line
  the diff names rather than landing one line past the end.

Two defects found while wiring this up and fixed here:

- `RuleEngine` stored whatever the provider returned without checking that every request was
  answered, so a provider that dropped a file left that path missing from `SyntacticEvidence`,
  which reads as "no rule asked for it" - the silent pass the evidence model forbids. Unanswered
  requests are now reconciled into explicit gaps under a new
  `SyntaxEvidenceGapReason.requestUnanswered` (`SyntacticEvidence.reconciled(with:)`).
- `regression-guard check` discarded `RuleEngine.Result.syntacticEvidenceGaps` entirely, so a
  degraded run was indistinguishable from a clean one outside of tests. The gaps are now named on
  stderr, one line per file, leaving stdout exactly what the chosen format promises. Serializing
  them into the report still belongs to Report version and compatibility.
- Unrelated crash, found by running the CLI over this branch's own diff:
  `DisabledOrSkippedTestRule` keyed the head file's functions with
  `Dictionary(uniqueKeysWithValues:)` and trapped on any test file holding an overload set. An
  overload set now keeps its test identity when any member of it still reads as a test, covered by
  two end-to-end scratch-repo tests.
- `EndToEndScratchRepoTests` was on XCTest, which `AGENTS.md` forbids, and the two new cases would
  have extended that. Converted to a Swift Testing suite. Eight other XCTest files remain and are
  untouched.
