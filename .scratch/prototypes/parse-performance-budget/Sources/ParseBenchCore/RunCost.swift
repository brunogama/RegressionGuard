import Foundation

/// What one pass over one diff cost.
///
/// The three quantities the budget is written in - spawns, syntax time against source bytes, and
/// peak resident - all come off this, which is why the input sizes are recorded alongside the
/// times rather than left to be inferred from the scenario name.
public struct RunCost: Sendable {
  public var files = 0
  /// Trees built: files present at base plus files present at head.
  public var parses = 0
  public var bytes = 0
  public var lines = 0
  public var subprocesses = 0
  /// Reading base source at the base ref.
  public var fetch = 0.0
  public var parse = 0.0
  /// A full `SyntaxAnyVisitor` sweep of every tree.
  public var walk = 0.0
  /// Building a `SourceLocationConverter` per tree and resolving one position through it.
  public var sourceLocation = 0.0

  public init() {}

  public var total: Double { fetch + parse + walk + sourceLocation }

  /// Parse, walk, and source-location time - everything the parser costs once the bytes are in
  /// hand, and the quantity the budget's second clause limits per MiB.
  public var syntaxWork: Double { parse + walk + sourceLocation }

  /// One tab-separated row, matching the header `ParseBench.header` prints.
  public func row(scenario: String, strategy: FetchStrategy, best: Double, peak: Int) -> String {
    func ms(_ value: Double) -> String { String(format: "%.1f", value * 1000) }
    func mib(_ value: Int) -> String { String(format: "%.2f", Double(value) / 1_048_576) }
    return [
      scenario,
      strategy.rawValue,
      "\(files)",
      "\(parses)",
      mib(bytes),
      "\(lines)",
      "\(subprocesses)",
      ms(fetch),
      ms(parse),
      ms(walk),
      ms(sourceLocation),
      ms(total),
      ms(best),
      String(format: "%.1f", Double(peak) / 1_048_576),
    ].joined(separator: "\t")
  }
}
