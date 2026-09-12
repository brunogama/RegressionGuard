import Foundation
import ParseBenchCore

/// One scenario to measure.
struct Arguments {
  var repo: String
  var base: String
  var head: String
  var label: String
  var repeats: Int
  /// Which base-fetch strategies to time.
  ///
  /// Selectable so the largest diffs can skip the per-file sweep when its point is already made:
  /// at one spawn per file it costs minutes.
  var strategies: [FetchStrategy]
  /// Print the column header before the rows.
  var printsHeader: Bool

  static let usage = """
    usage: parsebench --repo <path> --base <ref> --head <ref> \
    [--label L] [--repeat N] [--strategy per-file,batched] [--header yes]
    """

  static func fromCommandLine() -> Arguments {
    var values: [String: String] = [:]
    var rest = Array(CommandLine.arguments.dropFirst())
    while let flag = rest.first, flag.hasPrefix("--") {
      rest.removeFirst()
      guard let value = rest.first else { break }
      rest.removeFirst()
      values[String(flag.dropFirst(2))] = value
    }
    guard let repo = values["repo"], let base = values["base"], let head = values["head"] else {
      FileHandle.standardError.write(Data((usage + "\n").utf8))
      exit(2)
    }
    let strategies =
      (values["strategy"] ?? FetchStrategy.allCases.map(\.rawValue).joined(separator: ","))
      .split(separator: ",")
      .compactMap { FetchStrategy(rawValue: String($0)) }
    guard !strategies.isEmpty else {
      FileHandle.standardError.write(Data("no known strategy named\n".utf8))
      exit(2)
    }
    return Arguments(
      repo: repo,
      base: base,
      head: head,
      label: values["label"] ?? "\(base)..\(head)",
      repeats: values["repeat"].flatMap { Int($0) } ?? 5,
      strategies: strategies,
      printsHeader: values["header"] == "yes"
    )
  }
}
