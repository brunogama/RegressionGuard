Title: Swift-syntax version pin and grammar coverage
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

Which swift-syntax alignment series does the guard pin, and how is a grammar gap made visible instead of silent?

Supersedes the version-floor clause of the dependency posture decision. `from:` does not float across alignment series, so the pin is a maintained decision: 600.0.0 resolves to 600.0.1 while the current stable is 603.0.2. An under-selected version does not crash, it silently fails to represent newer syntax, so rules stop seeing constructs they were written to catch and the change passes.

Resolve which series to pin and what maintains it as toolchains move; how the guard detects that guarded source uses syntax its parser cannot represent, since that must surface as an inconclusive result rather than a pass; whether the selected major is recorded in the report envelope so a finding is traceable to the grammar that produced it; and whether the documented `SwiftSyntaxVersion` marker modules are worth using to support two series at once.

## Resolution

The guard pins the alignment series matching the current stable release, expressed as a half-open
range over that series: `"603.0.0"..<"604.0.0"`. A patch release inside a series cannot add
grammar, so those flow freely; the series itself is a decision a person makes, because `from:`
cannot express it. Both halves of the question text were confirmed against the live resolver
rather than taken on trust: `from: "600.0.0"` does resolve to 600.0.1, and a range admitting
everything resolves to 603.0.2. 603 is the series aligned with the Swift 6.3 toolchain this
package builds under, following the scheme where 509 parses Swift 5.9. 604 and 605 exist only as
prereleases and are not eligible.

What maintains the pin is the release of a new stable series, not a schedule, and the bump is the
same edit every time: raise both bounds by one. `SyntaxGrammar.pinnedAlignmentSeries` holds the
number so the decision lives in one place rather than only in the manifest, and so a run can
compare what it actually got against what the rules were written for.

### What an under-selected parser actually does

Measured, not assumed. One file containing `@Test(.disabled(...))`, `throws(E)`,
`nonisolated(nonsending)`, `@concurrent`, `~Copyable` and `[3 of Int]`, parsed by each series:

| | 600.0.1 | 603.0.2 |
|---|---|---|
| `tree.hasError` | true | false |
| unexpected node groups | 2 | 0 |
| missing tokens | 2 | 0 |
| parse diagnostics | 4 | 0 |

600.0.1 fails on `nonisolated(nonsending)` ("expected 'unsafe' in modifier") and on the
`[3 of Int]` InlineArray sugar, both Swift 6.2 syntax that guarded repositories write today.

Two findings from that run shape everything below. First, the failure is node-local: under 600,
`func handoff` reports an error while the `func example` beside it does not. A grammar gap can
therefore be scoped to the region it damages instead of condemning the file, and a rule keeps the
rest of the tree. Second, and more important, `hasError` is necessary but not sufficient.
`@concurrent` parsed clean under 600, because syntax that fits an existing open-ended production
- an attribute - lands in a well-formed node and is simply read wrong. Nothing in the tree
reveals it. **The pin is the defence and detection is the backstop, not the reverse.**

### How a gap is made visible

Per file, the guard asks whether the change reached syntax the parser could not represent.
`SyntaxNode.hasError` is node-local *by contract* - deliberately not swift-syntax's own recursive
`hasError`, because propagating it to the root would make every gap file-wide and unscopable.
`SyntaxTree.errorNodes(touching:)` narrows it to lines, and
`SyntacticEvidence.grammarGaps(for:)` intersects those with the diff's changed lines on that
side. A hit becomes a `SyntaxEvidenceGap` with the new reason `grammarUnrepresentable`, reported
on `RuleEngine.Result` beside the missing-evidence gaps and named on stderr by the CLI. A parse
error the change never touched costs the run nothing.

A tree that reports errors file-wide but localises none of them claims the whole changed region
instead. That closes an obligation this ticket would otherwise have left on the unbuilt parsing
target: a projection filling only the older file-level `hasParseErrors` would otherwise produce
no gap at all, which is a silent pass by omission.

Two causes land on the same reason code and the tree cannot separate them: source the author
genuinely malformed, and source newer than the grammar. Both cost the run the same thing, so both
are reported rather than guessed between. This does not overturn the migration contract's reading
of `hasParseErrors` as a confidence signal; it adds the case where that signal falls inside the
changed region, which is the only place a finding would have been raised. This is the `CONTEXT.md`
rule for evidence bundles applied to grammar: the region is inconclusive, never an implicit pass.

Per run, `SyntacticEvidenceProvider` now reports the grammar it parses with, and the CLI says so
when that series is older than the pin. This is the only available answer to the `@concurrent`
case, where no per-file signal exists at all.

### The report envelope

Yes, the selected major should be recorded, and the shape is settled: `SyntaxGrammar`, carrying
the alignment series always and the resolved version when the run can tell. It is absent rather
than a placeholder when the run had no parser, because a run with no grammar has none to name.
Without it a clean report from an under-selected parser is indistinguishable from a clean report
from a current one, which is exactly the silent degradation this ticket exists to prevent.

Serialising it is *not* done here. The value rides on `RuleEngine.Result` and stops there,
because Report version and compatibility owns the envelope and the text rule migration contract
already set the precedent, deferring `Violation.evidence` for the same reason and keeping
`GuardReport` at `schemaVersion: 1`. That ticket now inherits a second field.

### Marker modules

Not worth using to support two series at once. It would mean carrying conditional projection code
for grammars the guard has already decided it does not want to run against, and every `#if`
branch is a detection path that no test exercises on the other side - unusually bad odds for a
tool whose failure mode is silently seeing less.

They are worth using for one narrower thing, in the ticket that builds the parsing target:
`#if canImport(SwiftSyntax603)` lets that target report the series it was actually compiled
against, so the recorded grammar is observed rather than a literal that drifts from whatever
resolved. That is why `SyntaxGrammar` makes `version` optional and `alignmentSeries` required: the
series is what a marker module can establish, and inventing a patch number would be a lie.

### Accepted consequences

A guarded repository whose own dependency graph forces a lower swift-syntax loses resolution
rather than detection. The build fails loudly instead of the guard passing quietly, which is the
trade this project makes everywhere else.

A grammar gap does not change the exit status. Neither does any existing gap, and making them
blocking would fail every binary-distributed run, which has no parser at all. Whether an
inconclusive region should block is a policy question for Report version and compatibility, and
is deliberately not taken here.

The manifest itself is untouched. No parsing target exists yet, and `AGENTS.md` requires the
ticket that creates a target's sources to declare it. This ticket settles the pin and builds the
grammar-gap machinery RegressionGuardKit owns; the ticket adding the parsing target applies the
range and wires a real provider grammar to it.
