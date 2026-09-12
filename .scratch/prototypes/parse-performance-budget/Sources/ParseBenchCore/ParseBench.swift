import Foundation
import SwiftParser
import SwiftSyntax

/// One timed pass over one diff, in the shape the map decided on.
///
/// Head source is supplied already read and is left out of every phase: in a guard run it is the
/// checkout already sitting on disk, so charging it to the budget would invent a cost. Base source
/// is fetched through the strategy under test, then both sides are parsed, walked, and located -
/// which is everything `SyntacticEvidence` holds by the time a rule sees it.
public enum ParseBench {
  public static let header = [
    "scenario", "strategy", "files", "parses", "MiB", "lines", "subprocs",
    "fetch_ms", "parse_ms", "walk_ms", "location_ms", "total_ms", "best_ms", "peak_MiB",
  ].joined(separator: "\t")

  public static func measure(
    files: [ChangedFile],
    headSources: [String: String],
    repo: String,
    base: String,
    strategy: FetchStrategy
  ) -> RunCost {
    var result = RunCost()
    result.files = files.count
    GitCommand.resetCount()

    let basePaths = files.filter(\.existsInBase).map(\.path)
    var baseSources: [String: String] = [:]
    result.fetch = seconds {
      baseSources = strategy.sources(for: basePaths, repo: repo, ref: base)
    }
    result.subprocesses = GitCommand.count

    var sources: [String] = []
    for file in files {
      if let source = baseSources[file.path] { sources.append(source) }
      if let source = headSources[file.path] { sources.append(source) }
    }
    result.parses = sources.count
    result.bytes = sources.reduce(0) { $0 + $1.utf8.count }
    result.lines = sources.reduce(0) {
      $0 + $1.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    // Every tree stays alive to the end of the pass, because that is what a run does: the engine
    // resolves all files in one call and rules read from the result. Parsing and discarding would
    // measure a program nobody is going to write.
    var trees: [SourceFileSyntax] = []
    trees.reserveCapacity(sources.count)
    result.parse = seconds {
      for source in sources { trees.append(Parser.parse(source: source)) }
    }

    result.walk = seconds {
      for tree in trees {
        let visitor = NodeCountingVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
      }
    }

    result.sourceLocation = seconds {
      for tree in trees {
        let converter = SourceLocationConverter(fileName: "f.swift", tree: tree)
        _ = converter.location(for: tree.endPosition)
      }
    }

    return result
  }
}
