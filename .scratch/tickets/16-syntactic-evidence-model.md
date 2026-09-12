Title: Syntactic evidence model
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: 14-swift-syntax-dependency-posture, 15-swift-syntax-capability-research

## Question

How does syntactic evidence enter the evidence bundle, and what exactly does a rule receive?

`CONTEXT.md` defines the evidence bundle as diff-local signals plus optional repository-wide evidence, where missing optional evidence is explicit and never an implicit pass. Syntactic evidence is a third kind: a parsed tree for one file at one ref.

Resolve the shape a rule sees, how a rule declares it needs a tree so the runner can fetch and parse lazily, whether base and head trees arrive together as a pair, and what a rule receives when base source is missing, the file is newly added, or either ref fails to parse. The degradation path must stay explicit and auditable, and must not silently turn a would-be finding into a pass.

This decision fixes the `Rule` protocol's evaluation signature, which every other ticket on this map depends on.

Constrained by the dependency posture decision: RegressionGuardKit has no package dependencies and cannot parse. Rules receive already-parsed evidence produced by a target only the CLI depends on, so the evidence types must be expressible in Kit without importing swift-syntax.

Informed by Swift-syntax capability research: parsing is effectively free (0.125 ms mean per file) while reading a file at the base ref costs roughly 9 ms per subprocess, about 74x more. The lazy per-file shape assumed while charting must batch base-ref reads into a single invocation rather than one per file. Research also established that a diff hunk parsed in isolation yields no enclosing context, so whole-file base and head trees are required, not fragments.

## Resolution

Syntactic evidence is a third field on `EvidenceBundle`, so the `Rule` evaluation signature does
not change. `evaluate(evidence:context:)` stays as it is and every rule keeps receiving one
canonical bundle. What changes is what that bundle can carry, and one new static declaration.

A rule sees a structural projection, not a swift-syntax value. `SyntaxNode` carries a kind, a
physical `LineSpan`, an optional name, attribute names, the comment trivia written against it, and
its children; `SyntaxTree` wraps a root with the path and ref it came from plus a `hasParseErrors`
flag. The projection is Kit-native, which is what the dependency posture forces: RegressionGuardKit
has no package dependencies and cannot hold a `Syntax`. It is structural rather than a set of
per-rule pre-computed summaries, because rule logic has to stay in Kit - a summary type per rule
would move the detection into the parsing target and hollow out the library. `SyntaxNodeKind` is a
raw-string wrapper over swift-syntax's own `SyntaxKind` spelling with constants for the kinds the
in-scope families read, so a kind Kit has no constant for still survives the projection instead of
collapsing into an `unknown` case rules cannot tell apart.

A rule declares its need with `static var requiresSyntacticEvidence` and, if it wants to narrow
further than "every Swift file I can see", by overriding
`syntacticEvidenceRequests(for: FileDiff)`. The engine unions those requests across the enabled
rules, dedupes them, and resolves them in exactly one `SyntacticEvidenceProvider` call before any
rule evaluates. One call, not one per file: base-ref reads cost about 9 ms of subprocess each
against 0.125 ms to parse, so batching is part of the contract rather than an optimization. Lazy
stays true in the sense that matters - a run whose enabled rules ask for nothing parses nothing,
and ignored paths and approved changes are never requested at all.

Base and head always arrive together, as `SyntacticFileEvidence`. swift-syntax has no tree-diff
API, so every base-versus-head judgement is built by the rule from both sides, and a rule holding
only head could not tell a deletion from an absence.

Each side is a `SyntaxTreeAvailability` with three cases and no optional tree, because an optional
would let a gap read as an absence. `.parsed` carries a tree; error-tolerant parsing means this
also covers ill-formed source, where `hasParseErrors` is a confidence signal rather than a missing
side. `.absent(.fileAdded / .fileDeleted)` is the file legitimately having no source at that ref,
which a rule can reason about with full confidence. `.unavailable(reason, detail:)` is source that
should have existed and did not: `parserUnavailable` (no provider was injected, which is how a
binary-distributed Kit reaches rules), `sourceReadFailed`, `sourceNotDecodable`. Only the third
case is a gap. `isDegraded` tells a rule to fall back to line-based detection, and every
unavailable side becomes a `SyntaxEvidenceGap` on `RuleEngine.Result.syntacticEvidenceGaps`, so a
degraded run is reportable rather than indistinguishable from a clean one. A path missing from
`SyntacticEvidence` entirely means no rule asked for it, which `evidence(for:)` returning `nil`
keeps distinct from a requested file whose trees came back unavailable.

Requests name paths, not refs. The provider is constructed already knowing which refs it reads,
which keeps the working-tree case - where head is the checkout rather than a ref - expressible
without Kit modelling it. A request's `basePath`/`headPath` being nil encodes the expected absence,
and a rename carries a different path on each side.

Serializing gaps into the report is deliberately not done here. `GuardReport` is at
`schemaVersion: 1` and that bump belongs to Report version and compatibility;
`RuleEngine.Result` and `RegressionGuardRunner.evaluate(base:head:)` expose the gaps for it to
pick up. `RegressionGuardKit` ships no provider implementation: the swift-syntax-backed one waits
on the version pin, and until it lands `UnavailableSyntacticEvidenceProvider` makes a parser-less
run degrade visibly instead of behaving as though every file were clean.

## Implementation

- `Sources/RegressionGuardKit/Syntax/SyntaxTree.swift`: `LineSpan`, `SyntaxNodeKind`, `SyntaxNode`,
  `SyntaxTree`.
- `Sources/RegressionGuardKit/Syntax/SyntacticEvidence.swift`: `SyntaxTreeAvailability`,
  `SyntacticFileEvidence`, `SyntacticEvidence`, `SyntaxEvidenceGap`, `SyntacticEvidenceRequest`,
  `SyntacticEvidenceProvider`, `UnavailableSyntacticEvidenceProvider`.
- `EvidenceBundle.syntax` plus `withSyntacticEvidence(_:)`; `Rule.requiresSyntacticEvidence` and
  `Rule.syntacticEvidenceRequests(for:)`; `RuleEngine.Result` and `RuleEngine.evaluate(...)`;
  `RegressionGuardRunner.evaluate(base:head:)`. `check` and `run` are unchanged and delegate, so
  no public API breaks.
- 33 tests across `SyntaxTreeTests`, `SyntacticEvidenceTests`, `SyntacticEvidenceEngineTests`.

No swift-syntax dependency was added. The provider protocol has no production implementation yet,
which is the boundary this ticket stops at.
