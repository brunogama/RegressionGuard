import Foundation
import ParseBenchCore

// Measures what syntactic evidence costs for one real diff. See README.md for the scenario set
// behind the recorded table and for what each column means.

let arguments = Arguments.fromCommandLine()
let files = ChangedFile.inDiff(repo: arguments.repo, base: arguments.base, head: arguments.head)

guard !files.isEmpty else {
  FileHandle.standardError.write(Data("\(arguments.label): no Swift files in diff\n".utf8))
  exit(1)
}

if arguments.printsHeader { print(ParseBench.header) }

// Read once and left out of every timing: in a guard run head is the checkout already on disk.
let headSources = FetchStrategy.batched.sources(
  for: files.filter(\.existsInHead).map(\.path),
  repo: arguments.repo,
  ref: arguments.head
)

// Warm up so the first measured pass does not pay for lazily initialised parser state.
_ = ParseBench.measure(
  files: Array(files.prefix(5)),
  headSources: headSources,
  repo: arguments.repo,
  base: arguments.base,
  strategy: .batched
)

for strategy in arguments.strategies {
  var runs: [RunCost] = []
  for _ in 0..<arguments.repeats {
    runs.append(
      ParseBench.measure(
        files: files,
        headSources: headSources,
        repo: arguments.repo,
        base: arguments.base,
        strategy: strategy
      )
    )
  }
  // Sorted once and read twice, so the fastest pass and the median come from the same ordering
  // and cannot disagree. `repeats` is at least one, so the subscript is always in range.
  let ranked = runs.sorted { $0.total < $1.total }
  print(
    ranked[ranked.count / 2].row(
      scenario: arguments.label,
      strategy: strategy,
      best: ranked[0].total,
      peak: peakResidentBytes()
    )
  )
}
