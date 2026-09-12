Title: Swift-syntax syntactic evidence map
Labels: wayfinder:map
Status: open
Assignee: none

## Destination

Find the way to swift-syntax-backed detection in RegressionGuard: syntactic evidence as a first-class evidence kind alongside diff-local and repository-wide evidence, the five source-text rule families migrated onto it, the AST-only rule families it newly makes possible, and RegressionGuard's own rule tests rebuilt on real parsed Swift fixtures. This map carries planning and implementation; each open ticket still resolves one decision or prerequisite.

## Notes

- Domain: Swift CI guardrail package. Detection today is string matching over diff lines; this map moves it onto parsed syntax trees.
- Five of eight rule families read Swift source text and are in scope: disabled_or_skipped_test, weakened_assertion, production_code_deletion, control_flow_deletion, unchecked_error_path. The other three (coverage regression, characterization drift, review escape) and guard-configuration weakening read coverage JSON, snapshot paths, or YAML, and are untouched.
- Settled while charting: this map carries implementation, not just decisions.
- Settled while charting: rule scope is ALL candidates, both precision upgrades to existing rule IDs and the new AST-only families.
- Settled while charting: base-ref source is fetched and parsed lazily, only for files where a rule declares it needs syntactic evidence. Missing or unparseable source degrades to the line-based result and is reported explicitly, never as an implicit pass.
- Settled while charting: new rule IDs ship advisory by default; precision upgrades to existing rule IDs keep their current severity. Both ride a report-version bump, with promotion to blocking deferred to the existing ReportObserver calibration path.
- swift-syntax parses without a toolchain lock for plain parsing; SwiftParser is error-tolerant and yields a tree with missing nodes rather than failing.
- Consult skills during work: grilling, domain-modeling, tdd, swift-testing, swift-concurrency, ast-grep when designing detection shapes.
- Tracker: local Markdown under `.scratch/tickets/`; child relationship is the `Parent:` line and blocking uses `Blocked by:`.
- Naming rule: refer to tickets by title in human-facing summaries, with links when useful.
- Glossary: `CONTEXT.md` was untracked while this map was charted, so glossary edits were invisible to branches and pull requests. That was settled outside the map after the parse performance budget landed: it and the rest of the agent infrastructure - this tracker included - are now committed, so a glossary edit is reviewable like any other change.

## Decisions so far

<!-- one line per closed ticket -->

- [Swift-syntax dependency posture](14-swift-syntax-dependency-posture.md): parsing lives in a target only the CLI depends on, so RegressionGuardKit stays dependency-free and the XCFramework manifest keeps working; all three manifests stay at parity; version floor 600.0.0 permitting 601+; measured build cost is ~21s clean and is not a deciding factor.

- [Swift-syntax capability research](15-swift-syntax-capability-research.md): error tolerance is a stated guarantee; exact node kinds, SourceLocationConverter spans, and full trivia all support diff-scoped detection; parsing is effectively free while base-ref fetching dominates at roughly 74x; no toolchain lock for plain parsing, but an under-selected version degrades silently; no tree-diff API, no types, no cross-file resolution.

- [Syntactic evidence model](16-syntactic-evidence-model.md): syntactic evidence is a third field on `EvidenceBundle`, so the `Rule` evaluation signature does not change; rules see a Kit-native structural projection (`SyntaxNode`/`SyntaxTree`) rather than a swift-syntax value or per-rule summaries; a rule declares its need with `requiresSyntacticEvidence` and the engine resolves every declared file in one batched provider call; base and head always arrive paired; each side is `parsed` / `absent` / `unavailable` with no optional tree, and every unavailable side becomes a reported gap on `RuleEngine.Result`.

- [Source location to diff line mapping](17-source-location-to-diff-line-mapping.md): a node
  becomes a finding through `ChangedLineMap`, derived from the `FileDiff` a rule already holds; a
  node counts as changed only when a changed line falls inside its span on its own side, and
  straddling is answered by `NodeChangeScope` (`own` / `nested` / `outside`) off the node's own
  lines; base spans are translated to head lines, with a deleted line landing where its deletion
  left off and a deleted file honestly reporting no line at all; physical lines only, never
  `presumedLine`, and comments are read through a whole-subtree sweep over all four trivia cases.

- [Text rule migration contract](18-text-rule-migration-contract.md): a migrating rule adopts
  `SyntaxAwareRule` and splits its detections into three groups - answered by the diff, answered by
  the trees, and the text approximation of the second - and that split is the per-rule answer to
  what moves; the line path is retained as the degradation fallback for every detection that has
  one, because no provider exists yet and dropping it would make a parserless run a silent pass;
  `Violation.evidence` records `.diff` / `.syntax` / `.degradedDiff` so a degraded finding cannot
  pass itself off as the sharper one, and `GuardFinding` deliberately does not carry it yet;
  findings anchor only to nodes the change touched, with no fallback to one it did not; and every
  place a projection choice could have silently switched a detection off - a call's callee, a
  macro's `#`, attributes in either shape - is handled in the rule rather than left as an
  obligation on the unbuilt parsing target.

- [Swift-syntax version pin and grammar coverage](24-swift-syntax-version-pin-and-grammar-coverage.md):
  the pin is `"603.0.0"..<"604.0.0"`, the series aligned with Swift 6.3, held in
  `SyntaxGrammar.pinnedAlignmentSeries` and bumped by hand when a new stable series ships;
  measured, 600.0.1 cannot represent `nonisolated(nonsending)` or `[3 of Int]` while 603.0.2
  parses both, and the failure is node-local so a gap scopes to the region it damages; but
  `@concurrent` parses clean under 600, so `hasError` is a backstop and the pin is the defence;
  a change reaching an unrepresentable node raises `grammarUnrepresentable`, a tree with only
  file-level errors claims the whole changed region, and a provider reports its own series so the
  CLI can name an under-selected grammar; the series belongs in the report envelope but
  serialising it waits for report version and compatibility, and the manifest waits for the
  parsing target.

- [AST-only rule catalog](19-ast-rule-catalog.md): eight candidates in, three new advisory rule
  IDs out - `known_issue_suppression` (a suppression runs the test and absorbs its failure, so it
  is not a skip, and folding it into `disabled_or_skipped_test` would make it blocking on day
  one), `implementation_stubbed` (a real body replaced by a trap or constant, needing both trees
  so a newly added stub is not flagged), and `unreachable_assertion` (claiming only a literal
  `if false` and a block after an unconditional exit, advisory because reachability is
  undecidable from syntax); the test rename, `XCTSkip`, and force-unwrap candidates were already
  built into existing families, `try?` and a `guard` reduced to a bare `return` collapse into
  `error_handling_collapse` and are recorded as an amendment on the migration contract, and
  access-level widening is rejected outright as a design concern rather than an evidence one.

- [Report version and compatibility](22-report-version-and-compatibility.md): the envelope goes to
  `schemaVersion: 2`, carrying the two fields earlier tickets deferred to it - a finding's
  `evidence` and the run's `syntaxGrammar` - plus `syntacticEvidenceGaps`, so the artifact a
  repository audits cannot look identical whether the run parsed everything or nothing, and
  `rules`, which was not on the ticket and turned out to be what makes a silent family
  distinguishable from an absent one; the observer gains `hasReviewHistory` and now calibrates
  every rule that ran rather than only those that fired, since dropping a silent rule reads as a
  rule that was never there; adoption is a severity raise and deferral is `enabled: false`, both
  written into `regression-guard init`; and the upgrade note lives in `README.md` because "why is
  this red now" has to be answerable from the docs the repository already reads.

- [Parse performance budget](20-parse-performance-budget.md): re-measured on the pinned 603.0.2
  over nine real diffs up to 504 files and 15.31 MiB, lazy per-file parsing is viable as designed
  and nothing is forced beyond the batching already in the contract; the file count predicts
  nothing while source bytes predict everything, so the budget is one base-source read per run
  whatever the file count, 80 ms of syntax work per MiB parsed, and 10 MiB plus 60x the source held
  at once; the subprocess is the whole cost by a margin that grows with the diff, 47x at the
  smallest large scenario and 286x at the worst, but a binary that does nothing accounts for most
  of a spawn and the figure moves 6x with how the process is started, which is why the clause
  counts spawns rather than milliseconds; the capability research's 100 MB ceiling is superseded
  because `SyntacticEvidence` retains every tree for the run at about 50x its source, making
  retention rather than speed the live risk; and detection splits accordingly - clause one is
  already asserted by the engine's batching test, clauses two and three are re-measured by the
  harness, and wall-clock thresholds stay out of `swift test` because the same scenario read 42.6
  and 55.0 ms per MiB on two passes an hour apart, so a threshold tight enough to catch a real
  regression would teach the repository to ignore a red test.

- [Offline vendoring of swift-syntax](23-offline-vendoring-of-swift-syntax.md): offline builds carry
  syntactic evidence at full parity, so no consumer has to be told anything - the route is a
  vendored source checkout at `../swift-syntax` on a tag in the pinned series, reached through the
  path dependency `Package.local.swift` already uses, and a prepared copy builds and passes all 248
  tests with no network. The toolchain's own host modules parse correctly but are rejected: they
  ship no `SwiftSyntax<series>` marker module, so a target compiled against them cannot report its
  grammar and a working run becomes indistinguishable from a parserless one. Both source manifests
  declare swift-syntax now rather than deferring it, which required a target to consume it, so
  `RegressionGuardSyntax` lands here with the source-text half - `SwiftSyntaxProjection` and
  `CompiledSyntaxGrammar`, whose test asserts the resolved series against the pin - while the
  provider's git half stays for integration and `SyntacticEvidenceProvider` stays unimplemented
  rather than stubbed. `Package.binary.swift` gains nothing and should not. A path dependency gets
  no `Package.resolved` entry, so the vendored checkout's tag is its entire pin, and
  `prepare-offline-validation.py` verifies it against `SyntaxGrammar.pinnedAlignmentSeries` instead
  of substituting host modules. Cost is +13 MiB checked out, +385 MiB of build output and 3x the
  clean build, none of it paid incrementally - the "much larger checkout" the ticket assumed is 4x,
  not an order of magnitude.

- [Nested CLI package layout](25-nested-cli-package-layout.md): the dependency posture of
  ticket 14 was right about targets and wrong about consumers - SwiftPM resolves a consumer's whole
  package graph regardless of which product it uses, so a `GoldenMaster` test target was fetching
  80,542 objects and carrying 13.5 MiB of checkouts for a CLI it never builds. The published package
  now declares no dependencies at all, and the CLI, its parser, and its vendored repositories live
  in `RegressionGuardCLI/`, a nested package nothing can depend on because SwiftPM resolves from a
  repository root - the arrangement swift-syntax uses for `SwiftParserCLI`, verified by that same
  consumer resolving swift-syntax but not its nested package's swift-argument-parser. The consumer
  now resolves nothing: no `Package.resolved`, no checkouts, 52 KiB of cache against 67 MiB, with
  248 tests reconciled across the two roots as 234 + 14. The three alternate manifests and
  `prepare-offline-validation.py` are gone, replaced by one `REGRESSIONGUARD_OFFLINE` variable the
  CLI manifest reads - legitimate only because no consumer resolves that manifest, and for the same
  reason the strict flags moved into it, since on the command line they reach dependencies whose
  warnings this repository cannot fix. The plugin is the unpaid part: it sits in the nested package,
  so `swift package regression-guard` is unavailable to consumers until a release carries the
  artifact bundle and the root can name it through `.binaryTarget(url:checksum:)`, measured at 8 MiB
  paid by every consumer because binary artifacts download eagerly whether or not anything uses
  them.

## Not yet specified

- Promotion of advisory AST rule families to blocking, once per-rule false-positive rates exist. Depends on calibration data that cannot be gathered until the rules have shipped and been reviewed.
- Whether syntactic evidence enables precise, evidence-bounded fix-its in the agent remediation prompt, beyond the deterministic hints already decided. A tree makes concrete rewrites expressible for the first time.
- How syntactic evidence interacts with generated or vendored Swift that is in a guarded repository but not authored by it.
- When the command plugin becomes available to consumers again. The layout ticket settled the
  destination - the root declaring `.binaryTarget(url:checksum:)` against the artifact bundle
  `scripts/build-artifactbundle.py` already builds - but `url:` needs a published release to point
  at, so the plugin sits in the nested package and reaches nobody until one is cut.
- Whether a run should cap the source it retains at once. The parse performance budget measured a retained tree at about 50x its source and a 15.31 MiB diff peaking at 781.9 MiB, which fits a standard runner but not a small container. A cap means degrading part of a change to line-based detection, which is a policy question the budget ticket deliberately did not answer.

## Out of scope

- Type-aware or semantic analysis. swift-syntax is a syntax-only parser with no type information, so any rule requiring resolved types, protocol conformance checks, or cross-file symbol resolution needs a compiler, not this map.
- Syntactic evidence for non-Swift files. YAML workflow and guard-configuration parsing is a separate parser and a separate effort.
- A public Rule protocol or third-party AST rule extension API. The prior map already ruled that a later, separate proposal.
- Replacing the three non-Swift rule families, which gain nothing from a Swift parser.
