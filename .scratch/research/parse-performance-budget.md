# Parse performance budget

- **Method:** a re-runnable harness committed at
  [.scratch/prototypes/parse-performance-budget/](../prototypes/parse-performance-budget/), driven
  over nine real diffs. It reproduces the shape the map decided on: head source is already on disk
  (the CI checkout), base source is fetched from git, and every Swift file a rule asks about is
  parsed on both sides. Both base-fetch strategies are timed against the same file set.
- **Date:** 2026-09-12
- **Grammar:** swift-syntax 603.0.2, resolved from `"603.0.0"..<"604.0.0"` - the range
  [Swift-syntax version pin and grammar coverage](../tickets/24-swift-syntax-version-pin-and-grammar-coverage.md)
  pinned, and the re-measurement that ticket's resolution asked for.
- **Toolchain:** Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), arm64 macOS, `swift build -c release`,
  five warm-up files before timing, median of five repeats (one for the two largest per-file rows,
  noted below the table). The capability research measured on 6.4; this machine now carries 6.3.3,
  which is the release the pinned 603 series is aligned with, so this is the closer pairing of the
  two even though it is not a like-for-like re-run of that toolchain.
- **Quiet machine:** every row comes from a single `run.sh` pass with nothing else running.
  Timings here are sensitive enough to background load that a contaminated row reads as a 3x
  regression, so an earlier pass whose rows overlapped the spawn probe was discarded rather than
  merged into this one.
- **Supersedes:** the proposed budget in
  [Swift-syntax capability research](../tickets/15-swift-syntax-capability-research.md), which was
  measured on 600.0.1 and guessed at memory.

## Scenarios

Real diffs, picked by `survey.sh` for their Swift file counts rather than assembled. The first
five are this repository's own history; the rest are swift-syntax's, which is where diffs large
enough to hurt actually exist.

| scenario | what it is |
| --- | --- |
| `guard/1-file` | `edf6a4f`, a one-line plugin API change |
| `guard/6-file` | `f4b0336`, a rule fix across six files |
| `guard/13-file` | `21699c1`, the report envelope bump |
| `guard/26-file` | `b0780dc`, the source-text rule migration - this repository's largest real change |
| `guard/45-file` | `a301c1a`, a merge whose first-parent diff is 45 added files, so nothing is read at base |
| `swift-syntax/50-file` | `8ea19b601`, statement-level parser recovery |
| `swift-syntax/83-file` | `9e40b4022`, the largest single merge in recent history |
| `swift-syntax/243-file` | `602.0.0..603.0.0`, one alignment series to the next |
| `swift-syntax/504-file` | `600.0.0..603.0.0`, the deliberate worst case |

Scenario labels carry the file count the harness itself reports. It reads the diff with
`--no-renames`, so a rename counts as the two paths it really costs to fetch and parse;
`git diff --name-only` says 501 where the largest scenario says 504.

## Results

`parses` is files-with-base plus files-with-head, so it exceeds the file count wherever a file
exists on both sides. `MiB` and `lines` are the source actually parsed. Times are milliseconds,
median of five repeats; the per-file rows for the two largest scenarios are a single pass, because
at hundreds of spawns each repeat costs half a minute.

| scenario | strategy | files | parses | MiB | lines | subprocs | fetch | parse | walk | location | total | peak MiB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| guard/1-file | per-file | 1 | 2 | 0.00 | 64 | 1 | 79.1 | 0.2 | 0.0 | 0.0 | 79.4 | 9.7 |
| guard/1-file | batched | 1 | 2 | 0.00 | 64 | 1 | 79.3 | 0.2 | 0.0 | 0.0 | 79.5 | 9.8 |
| guard/6-file | per-file | 6 | 12 | 0.07 | 1,915 | 6 | 479.1 | 2.6 | 0.5 | 0.3 | 482.5 | 13.8 |
| guard/6-file | batched | 6 | 12 | 0.07 | 1,915 | 1 | 82.0 | 2.9 | 0.5 | 0.5 | 85.9 | 14.1 |
| guard/13-file | per-file | 13 | 20 | 0.07 | 2,164 | 7 | 564.2 | 3.9 | 0.7 | 0.5 | 569.3 | 14.6 |
| guard/13-file | batched | 13 | 20 | 0.07 | 2,164 | 1 | 81.5 | 3.7 | 0.7 | 0.5 | 86.4 | 15.0 |
| guard/26-file | per-file | 26 | 34 | 0.16 | 4,797 | 8 | 661.7 | 7.6 | 1.4 | 1.0 | 671.6 | 19.5 |
| guard/26-file | batched | 26 | 34 | 0.16 | 4,797 | 1 | 83.5 | 7.3 | 1.4 | 1.1 | 93.3 | 19.8 |
| guard/45-file | per-file | 45 | 45 | 0.12 | 4,116 | 0 | 0.0 | 6.4 | 1.2 | 0.9 | 8.6 | 18.0 |
| guard/45-file | batched | 45 | 45 | 0.12 | 4,116 | 0 | 0.0 | 6.3 | 1.2 | 0.9 | 8.4 | 18.0 |
| swift-syntax/50-file | per-file | 50 | 100 | 4.71 | 148,175 | 50 | 4,219.2 | 229.9 | 58.1 | 26.2 | 4,533.5 | 245.9 |
| swift-syntax/50-file | batched | 50 | 100 | 4.71 | 148,175 | 1 | 90.7 | 196.0 | 36.1 | 26.9 | 349.8 | 259.1 |
| swift-syntax/83-file | per-file | 83 | 166 | 2.30 | 74,607 | 83 | 6,746.7 | 89.7 | 19.0 | 13.6 | 6,869.1 | 120.5 |
| swift-syntax/83-file | batched | 83 | 166 | 2.30 | 74,607 | 1 | 91.6 | 89.5 | 16.4 | 14.2 | 211.7 | 123.7 |
| swift-syntax/243-file | per-file | 243 | 460 | 11.79 | 374,758 | 217 | 17,427.4 | 413.8 | 98.6 | 52.3 | 17,992.1 | 584.1 |
| swift-syntax/243-file | batched | 243 | 460 | 11.79 | 374,758 | 1 | 99.5 | 484.8 | 99.8 | 56.5 | 740.7 | 605.3 |
| swift-syntax/504-file | per-file | 504 | 897 | 15.31 | 486,851 | 401 | 31,741.8 | 539.4 | 211.7 | 67.2 | 32,560.1 | 757.2 |
| swift-syntax/504-file | batched | 504 | 897 | 15.31 | 486,851 | 1 | 111.0 | 551.8 | 101.9 | 72.3 | 837.0 | 781.9 |

Two readings the table has to be handed with. Peak resident is a process high-water mark, so the
batched row of each pair carries the per-file row's; read the per-file row for a clean number. And
a file the diff only added has no base side, which is why `subprocs` on the per-file rows sits
below the file count - 217 for 243 files, 401 for 504, and zero for the all-added `guard/45-file`.

### 1. Three constants, and none of them is the file count

The file count predicts nothing. 45 files cost 8.4 ms of syntax work; 50 files cost 259 ms. Source
bytes predict everything, across a 6.7x range of input size:

| quantity | measured | worst |
| --- | --- | --- |
| syntax work (parse + walk + location) per MiB | 47.4 - 66.7 ms | 66.7 ms |
| peak resident above a 9.7 MiB baseline, per MiB of source | 48.2x - 53.0x | 53.0x |
| parse throughput | 20.5 - 28.5 MiB/s, ~880k lines/s | - |

The five scenarios below 1 MiB are rounded to two decimals and are too coarse to read a ratio
from, so the ranges above come from the four large ones, both strategies each.

Mean parse per file on the worst case is **0.62 ms** across 897 parses - effectively the 0.6 ms
600.0.1 produced. Moving the pin from 600 to 603 did not change what parsing costs.

### 2. These coefficients are scales, not precision figures

The same scenario re-measured across passes moves substantially. `swift-syntax/50-file` batched
read 42.6 ms per MiB on one pass and 55.0 on another - a 29% spread on identical input, identical
binary, same machine, same hour. The memory ratio is far steadier, holding inside 10% across the
same passes.

This is not noise to be averaged away and forgotten; it is the most important fact about how this
budget can be enforced. A threshold tight enough to catch a real regression in syntax time would
fire on a quiet afternoon, and the budget below is set knowing that.

### 3. The subprocess is the whole cost, by a margin that grows with the diff

Per-file fetch against batched fetch, same file set, same work:

| scenario | per-file | batched | ratio |
| --- | ---: | ---: | ---: |
| swift-syntax/50-file | 4,219.2 ms / 50 spawns | 90.7 ms / 1 | 47x |
| swift-syntax/83-file | 6,746.7 ms / 83 spawns | 91.6 ms / 1 | 74x |
| swift-syntax/243-file | 17,427.4 ms / 217 spawns | 99.5 ms / 1 | 175x |
| swift-syntax/504-file | 31,741.8 ms / 401 spawns | 111.0 ms / 1 | **286x** |

The ratio is not a constant, because the two sides scale differently: per-file fetch is linear in
the file count at 79 - 84 ms a spawn, while batched fetch is one spawn plus about 0.08 ms per
object - 79.3 ms for a single file, 111.0 ms for 401. At the worst case that is half a minute of a
guard run against a tenth of a second.

The absolute per-spawn number depends on how the process is started, which is worth stating
because it varies by 6x on one machine:

| how | per invocation |
| --- | --- |
| `git show` from bash | 13.43 ms |
| `/usr/bin/true` through Foundation `Process` | 67.15 ms |
| `git show` through Foundation `Process` | 79.17 ms |
| `/usr/bin/env git show` through Foundation `Process` | 76.92 ms |
| one `git cat-file --batch` for all 30 files | 85.61 ms |

Almost all of it is process creation, not git: a binary that does nothing accounts for 67.15 ms of
the 79.17. The guard spawns through Foundation `Process`, so the higher figure is the one it pays;
a CI runner without this session's sandbox will land somewhere between the two. **The budget's
first clause therefore counts spawns, not milliseconds**, because the milliseconds are a property
of the host while the spawn count is a property of the code.

One adjacent finding, since the same table answers it: `GitRepository` resolves git through
`/usr/bin/env`, and that indirection is free - 76.92 ms against 79.17 is inside the noise. There is
nothing to win by resolving git directly.

### 4. Memory is the clause with teeth, and it was not measured before

`SyntacticEvidence` holds every parsed tree for the whole run by design - one batched provider
call, all files at once, rules read from the result. The harness models that faithfully, and it is
where the cost is: **a retained tree runs about 50x the size of the source it came from.** 15.31
MiB of parsed source peaked at 781.9 MiB.

The capability research proposed "peak resident under 100 MB". That number came from a harness
that parsed and discarded one file at a time, and an 83-file swift-syntax diff already breaks it at
120.5 MiB. It is superseded below.

## The budget

Three clauses, each set above the worst reading with enough margin to survive the run-to-run spread
measured in section 2.

1. **One base-source read per run, whatever the file count.** Not one per file, not one per rule.
   Measured at 47x to 286x on identical work, with the multiplier growing as the diff does.
2. **80 ms of syntax work per MiB of parsed source**, covering parse, a full-tree walk, and a
   `SourceLocationConverter` with a lookup. 20% over the worst measured 66.7, which is roughly the
   spread a quiet machine produces on its own.
3. **10 MiB fixed plus 60x the source held at once.** 13% over the worst measured 53.0, and the
   memory ratio is the steadier of the two.

Read against the changes the guard will actually see, that is unremarkable. This repository
averages 4.12 KiB across its 92 Swift files, so a 200-file change is roughly 0.8 MiB a side,
1.6 MiB parsed: one subprocess, ~110 ms of syntax work, ~105 MiB peak. The deliberate worst case -
504 files of largely generated Swift, 15.31 MiB - is one subprocess, 837 ms, and 781.9 MiB. That
fits a standard 2-core GitHub runner with room to spare. It does not fit a 512 MiB container, and a
repository that guards generated Swift is the one that would find out.

### What the numbers decide

- **Lazy per-file base parsing is viable exactly as designed.** Parsing is 0.62 ms per file at the
  worst case. It was never the cost and it still is not.
- **Batching is forced**, and is already the contract: `SyntacticEvidenceProvider` takes an array
  and `RuleEngine` resolves every rule's declared files in one call. Without it the worst case
  spends 31.7 seconds fetching, against 111 ms.
- **Concurrency is not justified.** The entire syntax phase is 726 ms at the deliberate worst case,
  against a guard run that already spends seconds in git and rule evaluation. Trees are immutable
  and safe to build in parallel, so the option stays open at no cost if a future rule set makes
  walking dominant. Nothing in this catalog does.
- **Caching is rejected a second time**, now for a better reason than the first. Re-parsing costs
  0.62 ms per file; a cache would buy that back by spending the one resource the budget is actually
  tight on.
- **The live risk is retention, not speed.** 50x is the number to watch, and it scales with what
  rules request rather than with anything the parser does.

### How a regression is detected

- **Clause 1 is detected by the test suite, today.**
  `SyntacticEvidenceEngineTests.requestsAreBatchedIntoOneCall` asserts the provider is called
  exactly once for a multi-file, multi-rule run. It is deterministic, it involves no clock, and it
  fails on the only change that could break the clause - a caller reaching for a per-file path.
- **Clauses 2 and 3 are detected by re-running the harness** and comparing against the table above.
  It is re-run when the alignment series is bumped, when the parsing target's provider changes, and
  when a rule changes what it requests - the three things that can move these numbers.
- **Wall-clock assertions are deliberately kept out of `swift test`.** Section 2 measured a 29%
  spread on identical input within one hour, and the spawn table varies by 6x depending only on how
  the process is started. A timing threshold in CI would fail for reasons that have nothing to do
  with the code, and a guard whose own suite cries wolf is teaching its repository to ignore a red
  test. That is the exact failure this package exists to catch, and it is not worth buying a
  performance tripwire with it.

## Confidence

High for the shape of all three constants - that cost tracks source bytes rather than file count,
and that retention rather than parsing drives memory - each measured across a 6.7x range of input
size. High for the conclusion that batching is required and caching is not, which follows from
ratios rather than absolutes, and which the 286x worst case makes hard to argue with. Medium for
the syntax-time coefficient as a number, explicitly: it moved 29% between passes, and the budget is
set with that spread allowed for. Explicitly low for absolute spawn cost, which is why the first
clause counts spawns instead. Medium for the 50x retention multiplier generalising to hand-written
Swift: the large corpora are swift-syntax's own sources, which are heavily generated and unusually
dense, though the 2.30 MiB and 15.31 MiB scenarios give the same ratio.
