import Commander
import Foundation
import RegressionGuardCommandLine
import RegressionGuardKit
import RegressionGuardSyntax

struct Check: ParsableCommand {
  static let commandDescription = CommandDescription(
    commandName: "check",
    abstract: "Diff two refs or compare a ref against the working tree."
  )

  @Option(name: .long, help: "Ref to compare against, such as origin/main or a SHA.")
  var base: String = "HEAD"

  @Option(name: .long, help: "Ref to check. Omit to check the working tree against --base.")
  var head: String?

  @Option(name: .long, help: "Repository directory. Defaults to the current directory.")
  var path: String = FileManager.default.currentDirectoryPath

  @Option(name: .long, help: "text, json, or github.")
  var format: String = "text"

  @Option(name: .long, help: "Write the versioned JSON report to this path.")
  var reportFile: String?

  @Option(name: .long, help: "Fail at or above this severity: info, warning, error.")
  var failOn: String = "error"

  init() {}

  /// Binds parsed options onto the declared defaults.
  ///
  /// Written out rather than reflected: Commander's wrappers carry the metadata but never receive
  /// a value, so this is the only place the two halves meet. Each default here is the one declared
  /// above, so an option the caller omits keeps the documented behaviour.
  init(options: ParsedOptions) {
    self.init()
    base = options.string("base", or: base)
    head = options.string("head")
    path = options.string("path", or: path)
    format = options.string("format", or: format)
    reportFile = options.string("reportFile")
    failOn = options.string("failOn", or: failOn)
  }

  func run() async throws {
    guard let threshold = Severity(rawValue: failOn) else {
      throw ValidationError("--fail-on must be one of: info, warning, error")
    }

    // The parser the libraries cannot carry. RegressionGuardKit declares the provider and ships
    // without one, so a run that does not inject it degrades every tree-reading detection and
    // finds nothing at all for the families that have no text fallback. This is where it arrives.
    let repositoryDirectory = URL(fileURLWithPath: path)
    let runner = RegressionGuardRunner(
      repositoryDirectory: repositoryDirectory,
      syntacticEvidenceProvider: GitSyntacticEvidenceProvider(
        repositoryDirectory: repositoryDirectory,
        baseRef: base,
        headRef: head
      )
    )
    let result = try await runner.evaluate(base: base, head: head)
    let violations = result.violations
    Self.reportEvidenceGaps(result.syntacticEvidenceGaps)
    Self.reportUnderSelectedGrammar(result.syntaxGrammar)
    let hasBlockingFinding = violations.contains { $0.severity >= threshold }
    let report = GuardReport(
      toolVersion: "0.1.0",
      repository: URL(fileURLWithPath: path).lastPathComponent,
      baseRef: base,
      headRef: head ?? "working-tree",
      runID: head ?? "working-tree",
      exitStatus: hasBlockingFinding ? 1 : 0,
      findings: violations,
      syntacticEvidenceGaps: result.syntacticEvidenceGaps,
      syntaxGrammar: result.syntaxGrammar,
      rules: result.reportedRules(failOn: threshold),
      approvalSuppressed: result.isApproved
    )

    if let reportFile {
      let data = try JSONReportFormatter().data(for: report)
      try data.write(to: URL(fileURLWithPath: reportFile))
    }

    if format == "json" {
      Console.write(try JSONReportFormatter().format(report))
    } else {
      Console.write(formatter.format(violations))
    }

    if hasBlockingFinding {
      throw ExitCode.failure
    }
  }

  /// Names every hole in the syntactic evidence on stderr, so a degraded run never looks clean.
  ///
  /// Stdout stays exactly the findings the chosen format promises. The report carries the same
  /// gaps in `syntacticEvidenceGaps`, so this is the human-facing half of a record that also
  /// survives in the artifact.
  private static func reportEvidenceGaps(_ gaps: [SyntaxEvidenceGap]) {
    guard !gaps.isEmpty else { return }
    let byPath = Dictionary(grouping: gaps, by: \.path)
    Console.writeError(
      "regression-guard: syntactic evidence incomplete for \(byPath.count) file(s) - "
        + "syntax-backed rules ran degraded and may have missed findings."
    )
    // A run with no parser at all fails identically for every file it looked at, so naming each
    // one says nothing the count above has not already said. Every other reason is per file and
    // worth reading.
    guard !gaps.allSatisfy({ $0.reason == .parserUnavailable }) else {
      Console.writeError("  no Swift parser was supplied to this run, so no file was parsed.")
      return
    }
    for (path, fileGaps) in byPath.sorted(by: { $0.key < $1.key }) {
      let refs = fileGaps.map(\.ref.rawValue).sorted().joined(separator: ", ")
      let reasons = Set(fileGaps.map(\.reason.rawValue)).sorted().joined(separator: ", ")
      let detail = fileGaps.compactMap(\.detail).first.map { " - \($0)" } ?? ""
      Console.writeError("  \(path) (\(refs)): \(reasons)\(detail)")
    }
  }

  /// Says so when the run parsed with an older grammar than the rules were written against.
  ///
  /// The gaps above only catch syntax the parser noticed it could not represent. Syntax that
  /// fits an existing open-ended production parses into a well-formed node and is simply read
  /// wrong, with nothing in the tree to show for it. Comparing the series is all that is left,
  /// and an unreported stale parser is a guard that quietly stopped looking.
  private static func reportUnderSelectedGrammar(_ grammar: SyntaxGrammar?) {
    guard let grammar, grammar.isUnderSelected else { return }
    Console.writeError(
      "regression-guard: parsed with swift-syntax \(grammar.alignmentSeries) "
        + "(Swift \(grammar.swiftRelease)), older than the "
        + "\(SyntaxGrammar.pinnedAlignmentSeries) this guard targets - "
        + "syntax newer than that grammar may be read incorrectly and missed entirely."
    )
  }

  private var formatter: ViolationFormatter {
    switch format {
    case "json": return JSONFormatter()
    case "github": return GitHubAnnotationFormatter()
    default: return TextFormatter()
    }
  }
}
