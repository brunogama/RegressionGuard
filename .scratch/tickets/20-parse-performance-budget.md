Title: Parse performance budget
Labels: wayfinder:task
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: 14-swift-syntax-dependency-posture, 16-syntactic-evidence-model

## Question

What does syntactic evidence cost per guard run, and what budget must it stay inside?

The guard runs on every pull request, so parse time is paid on every change. Lazy base-ref parsing means one source-fetch subprocess plus two parses for each Swift file a rule asks about, and a large refactor touching many files is the worst case.

Measure against real diffs of varying size, including a deliberately large one, and record parse time, subprocess count, and peak memory. Establish the budget the implementation must hold and how a regression against it is detected. This is manual work that unblocks a decision: the numbers determine whether lazy per-file parsing is viable as designed, or whether batching, concurrency, or caching is forced.

Baseline measured by Swift-syntax capability research, against swift-syntax 600.0.1 on a 6.4 toolchain: 44 repository files parsed in 5.5 ms total (0.125 ms mean); worst case 258 files, 5.9 MB, 165k lines in 154 ms total (0.6 ms mean, 7.3 ms max, 23 MB peak resident). Base-ref reads averaged 9.24 ms each across 26 sequential subprocesses. Parsing is not the cost; the subprocess is. These numbers also remove tree caching from consideration, which the map previously carried as unspecified. Re-measure against whichever alignment series is finally pinned.

## Resolution

Re-measured on the pinned series - swift-syntax 603.0.2 under Swift 6.3.3 - over nine real diffs
running from a one-line plugin change to 504 files and 15.31 MiB of source, both fetch strategies
timed against every scenario. Full tables, method, and the scenario list are in
[.scratch/research/parse-performance-budget.md](../research/parse-performance-budget.md); the
harness that produced them is at
[.scratch/prototypes/parse-performance-budget/](../prototypes/parse-performance-budget/) and is
re-runnable.

**Lazy per-file parsing is viable exactly as designed. Nothing is forced except the batching
already in the contract.** Parsing costs 0.62 ms per file at the worst case, effectively unchanged
from 600.0.1, so moving the pin cost nothing. What the file count does not predict, source bytes
do: 45 files cost 8.4 ms of syntax work while 50 files cost 259 ms, but syntax work per MiB stays
inside 47.4-66.7 ms and peak resident inside 48.2x-53.0x across a 6.7x range of input size. The
budget is three clauses: **one base-source read per run whatever the file count; 80 ms of syntax
work per MiB parsed; 10 MiB fixed plus 60x the source held at once.** For a 200-file change of
ordinary hand-written Swift - this repository averages 4.12 KiB per file, so 1.6 MiB parsed - that
is one subprocess, ~110 ms, and ~105 MiB.

The subprocess is the entire cost, and by a margin far wider than first measured because the two
sides scale differently. Per-file fetch is linear in the file count at 79-84 ms a spawn; batched
fetch is one spawn plus about 0.08 ms an object. At the worst case that is 401 spawns and 31.7
seconds against one spawn and 111 ms - **286x** - where the smallest large scenario gives 47x. The
absolute per-spawn figure is not a property of the code: it is 13.43 ms from a shell and 79.17 ms
through Foundation `Process`, and a binary that does nothing at all accounts for 67.15 ms of that
79.17. Process creation is the cost, not git. That is why clause one counts spawns rather than
milliseconds.

Two things changed relative to what the capability research proposed. Its "peak resident under
100 MB" is superseded: it was measured by a harness that parsed and discarded one file at a time,
while `SyntacticEvidence` holds every tree for the whole run by design, and an 83-file swift-syntax
diff already breaks 100 MB at 120.5 MiB. And the 504-file worst case peaked at 781.9 MiB, which
fits a standard runner comfortably but not a 512 MiB container - so the live risk in this feature
is retention, not speed, and it scales with what rules request rather than with anything the parser
does. Whether a run should cap what it retains is left open on the map rather than answered here,
because a cap means degrading part of a change to line-based detection, which is a policy question.

Concurrency is not justified: the whole syntax phase is 726 ms at the deliberate worst case, and
trees are immutable so the option stays open for free if a future rule set makes walking dominant.
Caching is rejected a second time and for a better reason than the first - re-parsing costs 0.62 ms
per file, and a cache would buy that back by spending the one resource the budget is tight on.

Regression against the budget is detected in two places, split by what can be asserted honestly.
Clause one already has a test: `SyntacticEvidenceEngineTests.requestsAreBatchedIntoOneCall` asserts
the provider is called exactly once for a multi-file, multi-rule run, which is deterministic and
involves no clock. Clauses two and three are proportions, re-measured by re-running the harness
against the recorded table when the alignment series is bumped, when the provider changes, or when
a rule changes what it requests. Wall-clock assertions are deliberately kept out of `swift test`,
and the measurement is what settles that rather than taste: the same scenario read 42.6 ms per MiB
on one pass and 55.0 on another, same machine and same hour. A threshold tight enough to catch a
real regression would fire on a quiet afternoon, and a guard whose own suite cries wolf teaches its
repository to ignore a red test - the exact failure this package exists to catch.

Two edits land in shipping source, both because this measurement made what was already written
there false: the `SyntacticEvidenceProvider` doc justified batching with the superseded 0.125 ms
and 9 ms figures, and `SyntacticEvidence` documented nothing about retention, which turns out to be
the tight side of the budget. The test that guards clause one now says so.
