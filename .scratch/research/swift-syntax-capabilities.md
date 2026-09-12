# Swift-syntax Capability Research

- **Method:** DeepAPI web search (`POST /v1/search/web`, six differently-phrased queries) and website scraping (`POST /v1/scrape/website`) against first-party swift-syntax documentation and repository sources, plus a local measurement harness built against swift-syntax on the Swift 6.4 toolchain installed on this machine.
- **Date:** 2026-09-12
- **Search request IDs:** `615d4183-124e-47c6-9dd3-e18853cccc8c`, `79d7d980-ebf4-4603-8099-119258e01cfd`, `cdd21f0f-5e7a-4dab-b9f3-3aad9c44625a`, `ed856e6e-9fad-4143-b549-5ebe84dbc298`, `ba71bbc0-8c53-40b2-87c7-3c9c18e3c0a6`, `869c2808-9dac-429a-bf3f-0332fc6c9dc6`
- **Scrape request IDs:** `0d8c5b3b-aa77-4389-a7a1-54c53b96388b`, `26f111d7-3ab6-41b1-a245-1db283769cc2`, `3f2ba6ad-d838-40db-bec9-6002420d3cbc`, `33d38fe0-25e2-46c1-93a4-4ee80fdfb6fc`
- **Local harness:** a throwaway SwiftPM executable in the session scratchpad that resolved swift-syntax, exercised SwiftParser, SyntaxVisitor, SyntaxAnyVisitor, Trivia, and SourceLocationConverter, and timed parses over two corpora. Not committed; every number below is reproducible from the recipe in "Measurement method".

## Findings

### 1. Version selection and toolchain coupling

1. **Releases are aligned to language releases by major number, and that alignment is the selection rule.** The package README states that "Releases of SwiftSyntax are aligned with corresponding language and tooling releases, for example the major version 509 of swift-syntax is aligned with Swift 5.9." Source: [swift-syntax README](https://swiftpackageindex.com/swiftlang/swift-syntax) (raw README fetched from the repository main branch).

2. **The current published releases are 603.0.2 (latest stable) and a 605.0.0 prerelease.** The package index lists 603.0.2 as the latest release and `605.0.0-prerelease-2026-06-26` as the latest beta, across 30 releases. Source: [swift-syntax on Swift Package Index](https://swiftpackageindex.com/swiftlang/swift-syntax).

3. **`from:` in a SwiftPM manifest does NOT float across the alignment series.** Measured locally: a manifest declaring `from: "600.0.0"` resolved to `600.0.1`, not to the latest 603.0.2, because SwiftPM's `from:` means up-to-next-major and each language alignment is a new major. Version selection is therefore an explicit, deliberate pin per alignment series, not something the resolver keeps current.

4. **There is no toolchain lock for pure parsing.** Also measured locally: swift-syntax 600.0.1 - three alignment series behind - built and ran correctly under `Apple Swift version 6.4 (swiftlang-6.4.0.27.1)`, parsing Swift 6 sources from this repository and from the swift-syntax checkout itself. The macro-plugin constraint that forces a version match does not apply to a library that only calls `Parser.parse`.

5. **The real constraint is grammar coverage, not a lock.** The first-party versioning article says plainly: "If a swift-syntax version is used that is older than the compiler's version, then swift-syntax will not be able to represent the new syntactic structures (like new statements) in the source file because it doesn't know about them." Source: [Updating a Macro to a New Major swift-syntax Version](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftsyntax/macro-versioning). For RegressionGuard this means an under-selected version does not crash; it silently degrades - new syntax lands in unexpected nodes and rules stop seeing it. That is exactly the failure mode the guard must never treat as a pass.

6. **Multi-version support is available if it is ever wanted.** The same article documents empty `SwiftSyntaxVersion<major>` marker modules that exist specifically so clients can branch with `#if canImport(SwiftSyntax510)`. This is the documented escape hatch if RegressionGuard ever needs to support two alignment series at once.

### 2. Error tolerance on partial or invalid source

7. **Resilience is a stated design guarantee, not an accident.** The SwiftParser documentation's design principles say the parser "will attempt to recover from syntax errors, maintaining as much of the program structure as is feasible. It has no side effects, and in particular produces no errors regardless of how ill-formed the input source text is. Instead, all errors are described in the syntax tree itself." Errors take exactly two forms: *unexpected nodes* for text that matches no grammar production, and *missing tokens* for grammar-required syntax that is absent. Source: [SwiftParser](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftparser).

8. **Source fidelity is also guaranteed, including for ill-formed input.** The same design principles state the tree "can be rendered back into text that is byte-for-byte identical to the original source. The parser must maintain this property, regardless of whether the input text was well-formed Swift code." Source: [SwiftParser](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftparser). The SwiftSyntax library article repeats this as the "Source Fidelity" tenet and adds the "Resilience" tenet describing missing and unexpected syntax. Source: [Working with SwiftSyntax](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftsyntax/working-with-swiftsyntax).

9. **Measured, this holds on every degenerate input RegressionGuard can realistically be handed.** Six malformed samples were parsed locally. Every one produced a `sourceFile` root, and every one round-tripped byte-for-byte:

   | sample | `hasError` | funcDecls recovered | round-trips |
   | --- | --- | --- | --- |
   | truncated function body | true | 1 | yes |
   | unbalanced brace | true | 1 | yes |
   | bare diff-hunk fragment | true | 0 | yes |
   | non-Swift garbage followed by valid code | true | 1 | yes |
   | empty file | false | 0 | yes |
   | half-written call expression | true | 0 | yes |

   Nothing threw and nothing returned nil. `hasError` is a usable per-file health flag, and an empty file is correctly *not* an error.

10. **Recovery is structured, not just tolerant.** Parsing `func f( {\n let x = 1\n` produced 2 missing tokens, reachable by walking with `viewMode: .all` and testing `TokenSyntax.presence == .missing`. `SyntaxTreeViewMode` has exactly three cases, documented in the source: `.sourceAccurate` (skips missing, visits unexpected - "useful for source code transformations like a formatter"), `.fixedUp` (visits missing, skips unexpected - "should be used for structural analysis of the syntax tree"), and `.all`.

11. **A diff hunk in isolation parses but must not be trusted structurally.** The fragment `    XCTAssertEqual(a, b)\n  }\n}\n` parsed with `hasError=true` and still yielded 1 `FunctionCallExprSyntax` - but zero enclosing function or type context. Rules that only need "was an assertion call added here" could work on a hunk; every rule that needs enclosing context (is this a test function, is this a guard body, is this a production declaration) cannot. Whole-file parsing of base and head is the only sound input.

### 3. Walking and comparing trees

12. **`SyntaxVisitor` is the right tool for per-file rule evaluation.** The first-party article: "A `SyntaxVisitor` can be used to walk source code from the root to its leaves. To inspect a particular kind of syntax node, a client needs to override the corresponding `visit` method accepting that kind of syntax. The visit methods are invoked as part of an in-order traversal ... To provide a post-order traversal, the corresponding `visitPost` methods can be overridden." Source: [Working with SwiftSyntax](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftsyntax/working-with-swiftsyntax). It is declared `open class SyntaxVisitor` with `SyntaxVisitorContinueKind` (`.visitChildren` / `.skipChildren`) returned from each visit, which gives rules cheap subtree pruning.

13. **`SyntaxAnyVisitor` is for kind-agnostic sweeps, and it is a subclass, not an alternative.** Declared `open class SyntaxAnyVisitor: SyntaxVisitor` with a single `visitAny(_ node: Syntax)` hook. Its own documentation comment warns that overriding a type-specific `visit` in a `SyntaxAnyVisitor` subclass suppresses `visitAny` for that kind unless the subclass calls `visitAny` itself. Use it for whole-tree census work (node counts, missing-node sweeps), not for rule logic.

14. **`SyntaxRewriter` is out of scope for detection.** The same article describes it as the tool for producing rewritten nodes: "Visitors that rewrite particular syntax nodes can be implemented as a subclass of `SyntaxRewriter`... and return a rewritten syntax node as a result." Since RegressionGuard reports and does not edit, `SyntaxRewriter` earns its place only if the map later pursues evidence-bounded fix-its, which is listed as not-yet-specified.

15. **There is no built-in tree-diff, so base-versus-head comparison is the rule author's job.** No first-party structural diff API appeared in the documentation, and none exists in the library surface. The tree is an immutable persistent structure ("It is always safe to manipulate a syntax tree across threads" - [Working with SwiftSyntax](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftsyntax/working-with-swiftsyntax)), which makes parallel base/head parsing safe but supplies no correspondence between the two trees. Comparison must be done by extracting a rule-specific summary from each tree - a declaration map keyed by name, an assertion count, a set of control-flow node kinds - and comparing those summaries. This is a direct, and favourable, replacement for the current `compareTestFunctions` line-scan in `DisabledOrSkippedTestRule`.

### 4. Positions and line/column

16. **`SourceLocationConverter` is the documented bridge, and it is tree-scoped.** Its documentation: "Converts `AbsolutePosition`s of syntax nodes to `SourceLocation`s, and vice-versa. The `AbsolutePosition`s must be originating from nodes that are part of the same tree that was used to initialize this class." Source: [SourceLocationConverter](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftsyntax/sourcelocationconverter). The current initializer is `init(fileName:tree:)`; `init(file:source:)` is deprecated. One converter must be built per parsed tree, so base and head each need their own.

17. **Line and column semantics are precisely specified in the source.** `SourceLocation.line` is "1-based"; `column` is "The UTF-8 byte offset from the beginning of the line where this location resides. 1-based."; `offset` is "The UTF-8 byte offset into the file", 0-based. Converting out-of-range positions is safe - "If the position is exceeding the file length then the `SourceLocation` for the end of file is returned. If position is negative the location for start of file is returned." Source: `Sources/SwiftSyntax/SourceLocation.swift` in swift-syntax.

18. **Nodes expose three distinct positions, and the choice matters for diff mapping.** `position` (start of leading trivia), `positionAfterSkippingLeadingTrivia`, and `endPositionBeforeTrailingTrivia` / `endPosition`. `SyntaxProtocol` provides `startLocation(converter:afterLeadingTrivia:)` defaulting to `true` and `endLocation(converter:afterTrailingTrivia:)` defaulting to `false`. Measured: for a call inside a test method, `positionAfterSkippingLeadingTrivia` mapped to line 5 column 5 and `endPositionBeforeTrailingTrivia` to line 5 column 24, giving a node an exact `[startLine, endLine]` span. That span, intersected with the set of changed line numbers already carried in `FileDiff.addedLines`, is a complete answer to the "Source location to diff line mapping" ticket for head-side findings.

19. **`#sourceLocation` directives are a trap that must be avoided explicitly.** `SourceLocation` carries both `line` and `presumedLine`, and `location(for:)` computes `presumedLine` from the last preceding `#sourceLocation` directive. Findings must be reported with `line` (the physical line), never `presumedLine`, or a generated file with location directives will report findings against line numbers that do not exist in the diff. Source: `Sources/SwiftSyntax/SourceLocation.swift`.

### 5. Trivia

20. **Trivia is fully retained and reachable, which is what the approval marker needs.** "SwiftSyntax is designed to represent not just text, but whitespace, comments, compiler directives ... The syntax tree holds on to every byte of information in the source text." Trivia is reachable via `TokenSyntax.leadingTrivia` and `trailingTrivia`. Source: [Working with SwiftSyntax](https://swiftpackageindex.com/swiftlang/swift-syntax/main/documentation/swiftsyntax/working-with-swiftsyntax).

21. **Measured: both attachment sites work for approval markers.** A file with `// regression-guard:approve deliberate skip` on its own line above a function and `// regression-guard:approve` at the end of a statement line yielded the first as `.lineComment` in the function declaration's *leading* trivia and the second as `.lineComment` in the throw statement's *trailing* trivia. A token-level sweep found both. A marker can therefore be attached to a specific node - the current implementation only checks commit messages via `RuleContext.isApproved`, so node-scoped approval is a genuinely new capability.

22. **There are four comment trivia cases, not one.** `TriviaPiece` declares `lineComment`, `blockComment`, `docLineComment`, and `docBlockComment` (alongside whitespace cases and `unexpectedText`). A marker scanner that matches only `.lineComment` will miss `///` and `/* */` placements. Source: `Sources/SwiftSyntax/generated/TriviaPieces.swift`.

23. **Trivia attachment rules are NOT documented, and that is a known first-party gap.** swift-syntax issue #2582, "Request for Documentation on Parsing Rules for Trivia in swift-syntax", is still open and says the libSyntax-era documentation "seems to have disappeared since the transition to swift-syntax", and that "Understanding what constitutes the trailing trivia of a preceding token and what becomes the leading trivia of a following token is essential for implementing tools that process code." Source: swift-syntax issue #2582, "Request for Documentation on Parsing Rules for Trivia in swift-syntax", in the `swiftlang/swift-syntax` issue tracker, opened 2024-04-01 and still open, labelled `enhancement`, with a maintainer reply on the same day. **Consequence:** approval-marker lookup must sweep both leading and trailing trivia of every token within a node's span, and must never assume a comment lands where intuition says it does. Any rule that relies on a precise attachment rule is relying on undocumented behaviour.

### 6. Parse cost

Two corpora, `swift build -c release`, arm64 macOS, Swift 6.4 toolchain, swift-syntax 600.0.1, five-file warm-up before timing, `DispatchTime.now().uptimeNanoseconds` around each phase.

**Corpus A - this repository (`Sources/` + `Tests/`), 44 files, 128 KB, 4,041 lines:**

| phase | total | mean/file | p50 | p90 | max |
| --- | --- | --- | --- | --- | --- |
| parse | 5.5 ms | 0.125 ms | 0.092 ms | 0.292 ms | 0.344 ms |
| full `SyntaxAnyVisitor` walk | 1.7 ms | 0.038 ms | - | - | - |
| build converter + one lookup | 1.1 ms | 0.025 ms | - | - | - |

Throughput 22 MB/s. Peak resident memory 11.7 MB. Largest file `DisabledOrSkippedTestRule.swift` (6,992 bytes, 222 lines) parsed in 0.306 ms.

**Corpus B - the swift-syntax sources themselves, 258 files, 5.9 MB, 165,505 lines (deliberate worst case, includes very large generated files):**

| phase | total | mean/file | p50 | p90 | max |
| --- | --- | --- | --- | --- | --- |
| parse | 154.1 ms | 0.597 ms | 0.164 ms | 2.169 ms | 7.263 ms |
| full walk | 53.2 ms | 0.206 ms | - | - | - |
| build converter + one lookup | 30.1 ms | 0.117 ms | - | - | - |

Throughput 36 MB/s. Peak resident memory 23.4 MB. Largest file 282,220 bytes / 8,741 lines parsed in 6.0 ms.

24. **Parsing is not the cost. Subprocess spawning is.** Measured in this repository, 26 sequential source-control `show` invocations took 240 ms - a mean of **9.24 ms per subprocess**, against a mean parse of 0.125 ms. Fetching one base-ref file costs roughly **74x** more than parsing it, and roughly 15x more than parsing the single largest file in the swift-syntax corpus.

25. **A defensible budget.** For a 100-Swift-file pull request with lazy base plus head parsing: 200 parses at 0.6 ms worst-case mean is ~120 ms, plus walks and converters, comfortably under 250 ms of parse work. The same run costs ~0.9 s in base-content subprocesses if each file is fetched with its own invocation. Proposed budget: **parse + walk + locate under 500 ms for a 200-file change, peak resident under 100 MB**, with base-content retrieval batched into a single plumbing invocation (the batched object-read command) rather than one subprocess per file. Tree caching, which the map lists as unspecified, is not justified by these numbers; batching the fetch is.

## Rule-by-rule capability dependency

### In-scope existing rule families

| Rule family | swift-syntax capability it depends on | What syntax alone cannot deliver |
| --- | --- | --- |
| `disabled_or_skipped_test` (`DisabledOrSkippedTestRule`) | `FunctionDeclSyntax.name` and `.attributes` to recover test identity; `ClassDeclSyntax.inheritanceClause` for `XCTestCase`; `FunctionCallExprSyntax.calledExpression` for `XCTSkip`; `AttributeSyntax` for `@Test` / `@Disabled`; base-tree declaration map for the removed-function comparison currently done by line scan | Whether a type actually conforms to a test protocol through a chain of inherited or extension conformances declared in another file. The inheritance clause is a written name, not a resolved conformance. A helper renamed and moved to another file is invisible. |
| `weakened_assertion` (`WeakenedAssertionRule`) | `FunctionCallExprSyntax` and `MacroExpansionExprSyntax` to count real assertion calls instead of substring hits; literal argument inspection for tautologies (`XCTAssertTrue(true)`, `#expect(true)`); base-tree assertion census for the removed-without-replacement check | Whether a non-literal argument is *semantically* tautological (`XCTAssertEqual(x, x)` is syntactic; `XCTAssertEqual(a, b)` where both resolve to the same constant is not). Whether a user-defined helper wrapping an assertion still asserts. Whether an assertion is reachable at runtime. |
| `production_code_deletion` (`ProductionCodeDeletionRule`) | Nothing of its own - it is a facade delegating to the two below | - |
| `behavior_deletion` / control-flow deletion (`ControlFlowDeletionRule`) | `IfExprSyntax`, `GuardStmtSyntax`, `ForStmtSyntax`, `WhileStmtSyntax`, `SwitchExprSyntax`, `ThrowStmtSyntax`, `DoStmtSyntax`/`CatchClauseSyntax`, `ReturnStmtSyntax` as node kinds, replacing the current keyword-substring match that fires on the word `return` inside a comment or string | Whether removed branches were dead code. Whether the behaviour moved to a caller or a new file. Cyclomatic significance requires no types, but *equivalence* of the before and after control flow does. |
| `error_handling_collapse` / unchecked error path (`UncheckedErrorPathRule`) | `ForceUnwrapExprSyntax` (exact, replacing the current `!`-regex that must special-case `!=` and prefix `!`), `TryExprSyntax.questionOrExclamationMark`, `CatchClauseSyntax` with an empty `CodeBlockItemListSyntax` | Whether a force-unwrap is provably safe. Whether a swallowed error is handled by an enclosing `Result` or logged elsewhere. Whether the unwrapped expression is even optional - that needs types. |

### Candidate new rule families

| Candidate rule | swift-syntax capability | Confirmed by local probe | What syntax alone cannot deliver |
| --- | --- | --- | --- |
| Test renamed off the `test` prefix | base-tree vs head-tree `FunctionDeclSyntax.name` map, plus `.attributes` for `@Test` | yes - `func helperWasATest ... attrs=[]` recovered with name and attribute list | That a renamed function is the *same* function. Without a stable identity, a rename and a delete-plus-add are indistinguishable; body similarity is a heuristic, not a resolution. |
| `XCTSkip` / `withKnownIssue` introduced | `FunctionCallExprSyntax.calledExpression` and `ThrowStmtSyntax` | yes - `call XCTSkip` at line 13, `call withKnownIssue` at line 14 | Whether the symbol called is the real XCTest one or a local shadow. Name resolution needs a compiler. |
| Assertion inside an unreachable branch | branch node kinds plus literal condition inspection (`if false`, `#if` inactive regions) | partially - node kinds are reachable; literal-false conditions are syntactic | General unreachability. Anything beyond a literal condition is a dataflow question. `#if` region activity depends on build settings the guard does not have. |
| Body replaced by `fatalError` / stub | `FunctionDeclSyntax.body.statements` count plus first-statement inspection | yes - `func boom ... bodyStmts=1 stubbedByFatalError=true` | Whether a one-statement body that is not `fatalError` is a stub. Whether a stub is an intentional protocol requirement placeholder. |
| `try?` swallowing errors | `TryExprSyntax.questionOrExclamationMark == .postfixQuestionMark` | yes - `try? (optional-try)` at line 6 | Whether the discarded error mattered. Whether the optional result is checked downstream. |
| Force-unwrap replacing error handling | `ForceUnwrapExprSyntax` in head, absence of matching `guard let` / `if let` / `do`-`catch` in base | yes - `force-unwrap` at line 9 | That the removed handling and the added force-unwrap concern the same value. That requires binding resolution. |
| `guard` body reduced to bare return | `GuardStmtSyntax.body.statements`, single `ReturnStmtSyntax` with nil expression | yes - `guard body bareReturn=true stmtCount=1` | Whether a bare return is wrong. A `guard ... else { return }` is idiomatic Swift; this rule is inherently advisory and needs the base-vs-head narrowing to mean anything. |
| Access level widened to bypass `@testable` | `DeclModifierListSyntax` on declarations (`public`, `internal`, `package`, `open`), `@testable` attribute on `ImportDeclSyntax` | yes - `class Svc ... modifiers=[public,final]`, `import App attrs=[@testable]` | **The core of the rule.** Syntax sees that a declaration became `public` and that some file imports the module `@testable`. It cannot see that the widened declaration is the one the test needed, that the test target imports *this* module, or that the widening was motivated by the test rather than by a legitimate API addition. Linking the two requires cross-file module and target resolution. |

### What a syntax-only parser cannot deliver, stated once

- **No type information.** No resolved types, no optionality, no overload resolution, no inferred generic arguments. Every rule above that reasons about "is this value optional" or "does this assertion compare equal things" is reasoning about spelling, not semantics.
- **No cross-file or cross-module symbol resolution.** A name in one file cannot be connected to its declaration in another. Inheritance and conformance are read as written names only. Extensions, typealiases, and re-exports are invisible.
- **No reachability or dataflow.** Dead branches, unused results, and whether a swallowed error is compensated for elsewhere are all outside the tree.
- **No build-configuration awareness.** `#if` regions are present in the tree as syntax but their activity depends on flags the guard does not model.
- **No stable identity across a rename.** The tree has no node identity that survives an edit; base-versus-head correspondence is always a heuristic the rule author constructs.

These are the same limits the parent map already recorded as out of scope, now confirmed against first-party sources rather than assumed.

## Repository alignment

- `Sources/RegressionGuardKit/Rules/DisabledOrSkippedTestRule.swift` already reaches for base and head content through `context.repository.show(ref:path:)` in `functionIdentityViolations`, and then hand-rolls `extractFunctions` / `hasTestAttribute` with a five-line lookback over raw strings. That is the single clearest candidate for replacement by a `SyntaxVisitor`, and it already establishes the lazy base-fetch call shape the map assumes.
- `Sources/RegressionGuardKit/Rules/UncheckedErrorPathRule.swift` carries a regular expression `[A-Za-z0-9_\)\]]\!` with hand-written exclusions for `!=`, prefix `!`, and implicitly-unwrapped type annotations. `ForceUnwrapExprSyntax` removes all three special cases.
- `Sources/RegressionGuardKit/Rules/ControlFlowDeletionRule.swift` matches the substrings `"if "`, `"return"`, `"catch"` and similar anywhere on a line, including inside comments and string literals. Node kinds eliminate that entire false-positive class.
- `Sources/RegressionGuardKit/Models.swift` types `Violation.line` as `Int?` and `Configuration.approvalMarker` as a plain string checked only against commit messages in `RuleContext.isApproved`. Node spans (finding 18) want a start and end line, and trivia-borne markers (finding 21) want a per-node approval check. Both are model changes, not rule changes.
- `Sources/RegressionGuardKit/Rules/Rule.swift` defines `EvidenceBundle` with `fileContents: [String: FileContentEvidence]` already holding old and new text per path. Syntactic evidence fits naturally as a lazily-populated sibling keyed the same way, which keeps the `Rule.evaluate(evidence:context:)` seam intact.

## Recommendation

Pin swift-syntax to one explicit alignment series matching the oldest Swift toolchain the guard must support, and treat the pin as a maintained decision rather than a resolver outcome - `from:` will not move it. Select at or above the toolchain used to build the guarded code, because an under-selected version degrades silently rather than failing. Record the selected major in the report envelope so a finding can be traced back to the grammar that produced it.

Parse whole files, never hunks, and always parse base and head separately with their own `SourceLocationConverter`. Evaluate rules with `SyntaxVisitor` subclasses returning `.skipChildren` to prune. Use `SyntaxAnyVisitor` only for census sweeps. Do not reach for `SyntaxRewriter` until and unless fix-its are on the table. Because there is no tree-diff, every base-versus-head rule should extract a small, explicitly-defined summary from each tree and compare summaries - never attempt node-level correspondence.

Map findings to diff lines by taking each node's `startLocation(converter:)` and `endLocation(converter:)`, using the physical `line` and never `presumedLine`, and intersecting that span with the changed line numbers already present in `FileDiff`. Treat a node whose span does not intersect the change as out of scope, which is what keeps the tool from reporting against code the author never touched. Read approval markers by sweeping both leading and trailing trivia across all four comment cases, because the attachment rules are undocumented upstream.

Set the performance budget on measured numbers: parse, walk, and locate for a 200-file change under 500 ms with peak resident under 100 MB. Spend the engineering effort on batching base-content retrieval into a single plumbing invocation, not on caching trees - the measurement says subprocess spawning costs about 74 times more per file than parsing does.

## Open implementation risks

- The measurement used swift-syntax 600.0.1 under a 6.4 toolchain. Re-measure once the alignment series is chosen; the absolute numbers should not move much, but the budget should be pinned to the version actually shipped.
- `hasError` is a per-tree boolean with no severity. A file with one stray token and a file that is half-truncated look identical through it. The degradation path must report *that* parsing was imperfect and still fall back to the line-based result, per the map's existing decision.
- Trivia attachment being undocumented upstream is a real maintenance exposure. Fixture tests must assert on observed attachment so that an upstream change breaks a test rather than silently losing approval markers.
- Nothing here measured the build cost of taking on swift-syntax, which is the subject of the separate dependency-posture ticket. It is substantial and the numbers above do not speak to it.
- A deleted node has no head position at all. Findings sourced only from the base tree have no head line to report, and the model must carry that case explicitly rather than defaulting to line 1.

## Measurement method

Reproducible without touching this repository: create a throwaway SwiftPM executable depending on swift-syntax, add `SwiftParser` and `SwiftSyntax`, build with `swift build -c release`, then time `Parser.parse(source:)`, a full `SyntaxAnyVisitor` walk, and `SourceLocationConverter` construction per file over a directory tree, after warming up on five files. Subprocess cost was measured by timing 26 sequential source-control object reads in this repository and dividing.

## Confidence

High for version alignment, error-tolerance guarantees, the visitor API surface, position and line/column semantics, and trivia representation - all come from first-party documentation or the library's own source, and the behavioural claims were additionally confirmed by local execution. High for the parse-cost and subprocess-cost numbers as measured, medium for their generalisation to other machines and CI runners. Medium for the per-rule capability mapping, which is a design judgement derived from those primitives rather than anything upstream asserts.
