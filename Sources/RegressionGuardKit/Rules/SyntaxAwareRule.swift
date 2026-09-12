import Foundation

/// A rule whose detection sharpens when parsed syntax is available and still runs when it is not.
///
/// Every migrated rule splits its detections into three groups, and the split is the contract:
///
/// - `diffViolations` reads the diff itself and gains nothing from a tree, so it always runs.
/// - `syntacticViolations` reads the parsed trees, and runs when both sides the change expects are
///   parsed.
/// - `textFallbackViolations` is the same question asked of source text, and runs only when the
///   trees are missing.
///
/// The fallback is retained on purpose. A run reaches rules without a parser in the ordinary
/// course - a binary-distributed RegressionGuardKit, an unreachable base ref - and dropping the
/// text path there would turn every one of those runs into a silent pass. What the fallback may
/// not do is pass itself off as the sharper answer: when a tree was asked for and did not arrive,
/// its findings are marked `ViolationEvidence.degradedDiff` and the gap that caused them is
/// reported on the run.
///
/// "Asked for and did not arrive" is the precise condition, and it is narrower than "ran on text".
/// A caller holding only a `FileDiff` never asked for anything, and neither did a rule for a file
/// it did not request, so those findings are ordinary `.diff` - there is no gap to report because
/// nothing is missing.
public protocol SyntaxAwareRule: Rule {
  /// Detections whose evidence is the diff itself. Always run, tree or no tree.
  func diffViolations(fileDiff: FileDiff, context: RuleContext) async -> [Violation]

  /// Detections that read the parsed trees.
  ///
  /// Synchronous by design: everything this needs was resolved in the engine's one batched
  /// provider call, and reaching for the repository from here would put back the per-file
  /// subprocess that batching exists to avoid.
  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation]

  /// The same detections as `syntacticViolations`, approximated on source text.
  func textFallbackViolations(fileDiff: FileDiff, context: RuleContext) async -> [Violation]
}

public extension SyntaxAwareRule {
  static var requiresSyntacticEvidence: Bool { true }

  /// The line-based path, whole.
  ///
  /// This is what a caller holding only a `FileDiff` gets, and what the compatibility facades
  /// call, so it stays the rule's complete text-only behaviour.
  func evaluate(fileDiff: FileDiff, context: RuleContext) async -> [Violation] {
    await diffViolations(fileDiff: fileDiff, context: context)
      + textFallbackViolations(fileDiff: fileDiff, context: context)
  }

  func evaluate(evidence: EvidenceBundle, context: RuleContext) async -> [Violation] {
    var violations: [Violation] = []
    for fileDiff in evidence.fileDiffs {
      violations += await diffViolations(fileDiff: fileDiff, context: context)
      violations += await resolvedViolations(
        fileDiff: fileDiff,
        syntax: evidence.syntax.evidence(for: fileDiff),
        context: context
      )
    }
    return violations
  }

  /// Picks the tree path or the text path for one file, and records which one answered.
  ///
  /// A file no rule asked about - a non-Swift path, a file this rule declined to request - is not
  /// degraded: nothing was expected and nothing is missing, so its text findings are ordinary
  /// `.diff` findings. A file that was requested and came back with a gap on either side is
  /// degraded, because the sharper answer was expected and did not arrive.
  private func resolvedViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence?,
    context: RuleContext
  ) async -> [Violation] {
    if let syntax, !syntax.isDegraded {
      return syntacticViolations(fileDiff: fileDiff, syntax: syntax, context: context)
        .map { $0.judged(on: .syntax) }
    }
    let fallback = await textFallbackViolations(fileDiff: fileDiff, context: context)
    guard syntax != nil else { return fallback }
    return fallback.map { $0.judged(on: .degradedDiff) }
  }
}
