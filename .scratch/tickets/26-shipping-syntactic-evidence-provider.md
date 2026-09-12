Title: Shipping syntactic evidence provider
Labels: wayfinder:task
Status: closed
Assignee: none
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

What actually parses, in a real run?

Everything this map built is wired except the one piece that reads source. `RegressionGuardKit`
declares `SyntacticEvidenceProvider` and cannot implement it; the engine calls it in one batch and
reports the gaps; the rules read the trees; the CLI prints the gaps and the grammar; the projector
turns Swift into `SyntaxTree`. Nothing supplies the provider, so `RegressionGuardRunner` is
constructed without one in `CheckCommand` and every run takes the `UnavailableSyntacticEvidenceProvider`
path: every requested file is a `parserUnavailable` gap, every tree-reading detection degrades, and
the three AST-only families - which have no text fallback - find nothing by construction.

The route is decided; what remains is the implementation and the shapes it has to get right.

- **One batch, not one read per file.** The parse performance budget measured `git cat-file --batch`
  for a 504-file diff at 111 ms against 31.7 s for a `git show` per file. A per-file provider would
  make the subprocess the entire cost of the feature, so the batch is the contract.
- **The provider is built already knowing its refs**, so a request names only paths. That is what
  keeps the working-tree run - where head is the checkout rather than a ref - expressible without
  RegressionGuardKit modelling it.
- **The three outcomes stay apart.** A side the request never expected is an absence, a side that
  was expected and could not be read is a gap, and anything else is a tree. Collapsing the first
  two is the silent pass this evidence model exists to prevent.
- **The provider names its grammar**, so an under-selected series is visible in the report rather
  than showing up as detections that quietly stop firing.

## Acceptance

- A real `regression-guard check` over a repository with a Swift change parses it: no
  `parserUnavailable` gaps, and the report names the grammar.
- The AST-only families fire through the CLI, end to end, against a repository on disk.
- One subprocess per run for base-ref source, whatever the file count, asserted rather than assumed.
- A file that cannot be read at a ref is a gap naming the ref and the path, and a file that legitimately
  does not exist on a side is an absence.
- The working-tree run reads head from the checkout, including a file not yet committed.

## Resolution

`GitSyntacticEvidenceProvider` reads the source and `CheckCommand` injects it, so a real run parses.

The provider is built with its refs and answers a request naming only paths. Every object the run
needs - both sides of every requested file - is named once and read in a single `git cat-file
--batch`, wrapped in `GitObjectBatch`. That reader is synchronous, which is what the protocol asks
for and costs nothing: there is one spawn per run, so an actor around it would buy a hop and no
concurrency. The request is written from another thread while the answer is drained on this one,
because git answers as it reads and filling either pipe deadlocks a write-then-read - at the file
counts this exists to serve, long before the 504-file diff the budget measured.

Pairing the answers back to the requests is by position, which is the only link git gives: a found
object's header names its oid, not the path asked for. A malformed or truncated answer stops the
walk and every unpaired name becomes a failure, because a provider that silently returns nothing for
a requested file is indistinguishable from a clean one.

A `nil` head is the working tree, read from the checkout rather than from a ref, which is how
`regression-guard check --base main` runs with no head ref at all - including files never committed.

### Measured

| | |
|---|---|
| git invocations for source, 8 changed files | 1 |
| `parserUnavailable` gaps in a real run | 0 |
| grammar named in the report | 603 |

All four assertions are made against the built binary rather than the library, because the defect
this ticket existed to fix lived in neither: every layer had passing tests while `CheckCommand`
constructed its runner without a provider. The `implementation_stubbed` case is the sharpest of
them - that family has no text fallback, so the finding cannot exist by any route other than a tree
that really arrived.

The spawn count is asserted rather than assumed, by running the binary with `PATH` pointing at a
shim that records each `git` before execing the real one. The environment is set on the child, so
the assertion does not depend on test isolation.

### Also here

`ScratchRepository` now holds the repository, commit, run-the-binary and read-the-report helpers the
end-to-end suites share; `EnforcementWeakeningEndToEndTests` moved onto it and lost its private
copies. The report is decoded through a fixture type rather than through `GuardReport`, so a field
that never reached the file cannot read as one that did.
