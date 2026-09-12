# Parse performance budget harness

Measures what syntactic evidence costs per guard run. It is the regression detector for clauses 2
and 3 of the budget recorded in
[.scratch/research/parse-performance-budget.md](../../research/parse-performance-budget.md); clause 1
is detected by `SyntacticEvidenceEngineTests.requestsAreBatchedIntoOneCall` in the package's own
suite and needs nothing from here.

It is its own package on purpose. It has to depend on swift-syntax to measure it, and
RegressionGuardKit is dependency-free by decision.

## Running it

```bash
swift build -c release
./run.sh                                  # the scenarios behind the recorded table
./.build/release/spawnprobe <repo>        # where a subprocess's cost actually goes
./spawn.sh <repo>                         # the same comparison from a shell, for contrast
```

`run.sh` prints a header and one tab-separated row per (scenario, base-fetch strategy). Compare it
against the table in the research note; the three constants there - ms of syntax work per MiB,
peak resident per MiB of source, and the spawn count - are what a regression shows up in.

`run.sh` reads swift-syntax's own checkout for its large scenarios, so `swift build` has to have
resolved it first. It takes several minutes: the per-file sweep at the two largest sizes is
thousands of subprocesses, and it is run anyway, because reading the worst case only through the
strategy already known to win would prove nothing.

## When to re-run it

- The pinned alignment series moves (`SyntaxGrammar.pinnedAlignmentSeries`), and `Package.swift`
  here moves with it.
- The parsing target's `SyntacticEvidenceProvider` implementation changes.
- A rule changes what it requests, since retained source is what the memory clause is written in.

## Reading a row

| column | meaning |
| --- | --- |
| `files` | Swift files in the diff |
| `parses` | trees built - files present at base plus files present at head |
| `MiB`, `lines` | source actually parsed, both sides |
| `subprocs` | git invocations charged to the fetch phase |
| `fetch_ms` | reading base source at the base ref |
| `parse_ms` | `Parser.parse(source:)` over every side |
| `walk_ms` | a full `SyntaxAnyVisitor` sweep of every tree |
| `location_ms` | building a `SourceLocationConverter` per tree and resolving one position |
| `total_ms`, `best_ms` | median and fastest of the repeats |
| `peak_MiB` | process high-water resident, so the second row of a pair carries the first's |

Head source is fetched once before timing starts and left out of every phase: in a guard run it is
the checkout already on disk, and charging it to the budget would invent a cost.

Scenario labels carry the file count the harness itself reports, which counts a rename as two
paths. `git diff --name-only` will say 501 where the largest scenario says 504.

## Files

| file | what it does |
| --- | --- |
| `Sources/ParseBenchCore/` | the measurement itself, shared by both executables |
| `Sources/parsebench/` | the driver: one diff, the selected fetch strategies, four timed phases |
| `Sources/spawnprobe/` | four shapes of the same 30 reads, separating process creation from git's work |
| `run.sh` | the scenario set behind the recorded table |
| `survey.sh` | lists a repository's commits by Swift files touched, for picking scenarios |
| `spawn.sh` | the same spawn comparison from a shell, which pays a different process-creation cost |

## Conventions

`AGENTS.md`'s source-organization rules are followed here - one type per file, files under the
line budget, `swift-format` clean - even though `.swiftlint.yml` limits linting to `Sources` and
`Benchmarks` and so covers none of this. The numbers this harness prints are quoted as fact in
`SyntacticEvidence.swift`, so its correctness is not throwaway even though the package is.
