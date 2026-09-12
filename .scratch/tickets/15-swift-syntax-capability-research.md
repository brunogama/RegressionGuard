Title: Swift-syntax capability research
Labels: wayfinder:research
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

What does swift-syntax actually give us for diff-scoped regression detection, and what are its limits?

Resolve by collecting sourced findings on: version selection against a Swift 6 toolchain and whether any lock applies to non-macro parsing; SwiftParser's error-tolerance guarantees on partial or syntactically invalid source; the API for walking and comparing trees (SyntaxVisitor, SyntaxAnyVisitor, SyntaxRewriter) and which fits rule evaluation; how absolute source positions and line/column are obtained (SourceLocationConverter) for mapping findings back to diff lines; trivia handling, since comments and whitespace carry approval markers; and observed parse cost per file so a performance budget can be set.

Record which capabilities each in-scope rule family depends on, and name anything the candidate rules assume that a syntax-only parser cannot deliver. This is AFK research.

## Resolution

swift-syntax gives RegressionGuard four things it does not have today, and all four were confirmed against first-party documentation and by running the library locally on the Swift 6.4 toolchain. First, an error-tolerant parse with a stated guarantee: SwiftParser "produces no errors regardless of how ill-formed the input source text is", recording problems as missing tokens and unexpected nodes inside the tree, and rendering back byte-for-byte identical source even for broken input. Six deliberately malformed samples - truncated bodies, unbalanced braces, a bare diff hunk, non-Swift garbage - all produced a usable `sourceFile` root and all round-tripped. Second, exact node kinds in place of substring matching, which removes whole false-positive classes the current rules must special-case by hand. Third, `SourceLocationConverter` mapping any node position to a 1-based physical line, giving every finding a `[startLine, endLine]` span that can be intersected with the changed lines already carried in `FileDiff`. Fourth, full trivia retention, so an approval marker in a comment is reachable from the node it annotates rather than only from the commit message.

The limits are equally concrete. There is no toolchain lock for plain parsing - swift-syntax 600.0.1 built and ran fine under Swift 6.4, three alignment series newer - but there is a grammar-coverage floor: upstream states that a swift-syntax older than the compiler "will not be able to represent the new syntactic structures", which degrades silently rather than failing. `from:` in a manifest does not float across alignment series, so the version is a maintained decision. There is no tree-diff API, so base-versus-head comparison must be built from rule-specific summaries. Trivia attachment rules are undocumented upstream and the request for that documentation is still open, so marker lookup must sweep both leading and trailing trivia across all four comment cases. And the hard ceiling stands: no type information, no cross-file symbol resolution, no reachability, no stable node identity across a rename. The access-level-widening candidate is the rule most damaged by this - syntax sees that a declaration became `public` and that some file imports `@testable`, but cannot link the two.

Performance is not the risk the map worried about. Measured on this repository: 44 files, 128 KB, 5.5 ms total parse, 0.125 ms mean. On a deliberate worst case - the swift-syntax sources themselves, 258 files, 5.9 MB, 165k lines - 154 ms total parse, 0.6 ms mean, 7.3 ms for the single worst file, 23 MB peak resident. Against that, 26 sequential source-control object reads in this repository averaged 9.24 ms each. Fetching a base-ref file costs about 74 times more than parsing it. Lazy per-file base plus head parsing is viable exactly as designed; what is not viable is one subprocess per file. The proposed budget is parse, walk, and locate under 500 ms for a 200-file change with peak resident under 100 MB, with base-content retrieval batched into a single plumbing invocation. Tree caching is not justified by these numbers.

Full findings, sources, request IDs, the per-rule capability table for all five in-scope families and all eight candidates, and the measurement recipe are in [.scratch/research/swift-syntax-capabilities.md](../research/swift-syntax-capabilities.md).
