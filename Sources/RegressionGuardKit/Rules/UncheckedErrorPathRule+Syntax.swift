import Foundation

/// The syntactic contract for `error_handling_collapse`.
///
/// Both detections move to the tree:
///
/// - A force-unwrap becomes a `forceUnwrapExpr` the change touched, instead of a regular
///   expression over a line's characters. The regex already carries three carve-outs for `!=`, a
///   leading `!`, and an implicitly-unwrapped type annotation, and still matches a `!` inside a
///   string literal or a comment. A node is a force-unwrap or it is not.
/// - A swallowed `catch` becomes a `catchClause` whose body holds nothing, so a catch that spans
///   several lines, or that holds only a comment excusing itself, is caught - and the finding
///   carries the line, which the text path has no way to produce because it matches across the
///   added lines joined together.
///
/// The force-unwrap family named as an AST-only candidate elsewhere lands here rather than under a
/// new rule ID: `error_handling_collapse` already owns it, so sharpening it is a precision upgrade
/// and keeps the rule ID and severity a guarded repository already configured.
public extension UncheckedErrorPathRule {
  func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.isProductionPath(fileDiff), let head = syntax.headTree else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap
    return forceUnwrapViolations(
      in: head,
      map: map,
      path: fileDiff.displayPath,
      severity: severity
    )
      + swallowedCatchViolations(
        in: head,
        map: map,
        path: fileDiff.displayPath,
        severity: severity
      )
      + optionalTryViolations(
        in: head,
        map: map,
        path: fileDiff.displayPath,
        severity: severity
      )
      + collapsedGuardViolations(in: syntax, map: map, severity: severity)
  }

  private func forceUnwrapViolations(
    in head: SyntaxTree,
    map: ChangedLineMap,
    path: String,
    severity: Severity
  ) -> [Violation] {
    head.nodes(ofKind: .forceUnwrapExpr)
      .filter { map.touches($0.span, at: .head) }
      .map { node in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: path,
          line: map.reportLine(for: node.span, at: .head),
          message: "Force-unwrap introduced instead of proper error/optional handling.",
          detail: node.name.map { "`" + $0 + "` is force-unwrapped." }
        )
      }
  }

  /// A `catch` whose body holds no statements.
  ///
  /// A body projected with no `codeBlock` at all is left alone rather than assumed empty: an
  /// unrecognised projection is not evidence that the error is discarded.
  private func swallowedCatchViolations(
    in head: SyntaxTree,
    map: ChangedLineMap,
    path: String,
    severity: Severity
  ) -> [Violation] {
    head.nodes(ofKind: .catchClause)
      .filter { map.touches($0.span, at: .head) && Self.swallowsTheError($0) }
      .map { node in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: path,
          line: map.reportLine(for: node.span, at: .head),
          message: "Empty `catch` block introduced - the error is now silently discarded.",
          detail: nil
        )
      }
  }

  private static func swallowsTheError(_ node: SyntaxNode) -> Bool {
    guard let body = node.firstNode(ofKind: .codeBlock) else { return false }
    // `statements`, not `children`: a projection that keeps swift-syntax's statement list as a
    // node of its own gives an empty body exactly one child, which would read as "not empty" and
    // switch this detection off without a test going red.
    return body.statements.isEmpty
  }

  /// A `try?` the change introduced.
  ///
  /// `try?` discards the error outright, which is the same collapse a force-unwrap makes and is
  /// reported the same way: on introduction, without asking what the base did, because writing
  /// one is the act being flagged.
  ///
  /// Optionality is legible only through the node's spelling, since the projection has a single
  /// `tryExpr` kind for `try`, `try?`, and `try!`. That is a documented obligation on the
  /// projector rather than something this rule can absorb, and it is pinned by a fixture.
  private func optionalTryViolations(
    in head: SyntaxTree,
    map: ChangedLineMap,
    path: String,
    severity: Severity
  ) -> [Violation] {
    head.nodes(ofKind: .tryExpr)
      .filter { Self.discardsTheError($0) && map.touches($0.span, at: .head) }
      .map { node in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: path,
          line: map.reportLine(for: node.span, at: .head),
          message: "`try?` introduced - the error is discarded rather than handled.",
          detail: "Handle the error, or propagate it with `try`."
        )
      }
  }

  private static func discardsTheError(_ node: SyntaxNode) -> Bool {
    node.name?.hasPrefix("try?") ?? false
  }

  /// A `guard` whose failure branch used to do something and now only returns.
  ///
  /// Base-relative on purpose. `guard let x else { return }` is ordinary Swift, and flagging
  /// every one of them would bury the rule; what this catches is a branch that used to throw,
  /// trap, or report, and was quietly reduced. Guards are matched between the trees by their
  /// condition, since position moves and nothing else identifies them.
  private func collapsedGuardViolations(
    in syntax: SyntacticFileEvidence,
    map: ChangedLineMap,
    severity: Severity
  ) -> [Violation] {
    // No base tree means nothing to have been reduced from: a new file's guards are all new.
    guard let base = syntax.baseTree, let head = syntax.headTree else { return [] }
    let path = syntax.path
    let wasSubstantial = Set(
      base.nodes(ofKind: .guardStmt)
        .filter { !Self.returnsBare($0) }
        .compactMap(\.name)
    )

    return head.nodes(ofKind: .guardStmt)
      .filter { map.touches($0.span, at: .head) && Self.returnsBare($0) }
      .filter { $0.name.map(wasSubstantial.contains) ?? false }
      .map { node in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: path,
          line: map.reportLine(for: node.span, at: .head),
          message: "`guard` failure branch reduced to a bare `return`.",
          detail: node.name.map { "`guard " + $0 + "` no longer reports the failure." }
        )
      }
  }

  /// - Returns: `true` when the branch holds exactly one valueless `return`.
  private static func returnsBare(_ node: SyntaxNode) -> Bool {
    guard let body = node.firstNode(ofKind: .codeBlock) else { return false }
    let statements = body.statements
    guard statements.count == 1, let only = statements.first else { return false }
    return only.kind == .returnStmt && only.children.isEmpty && only.name == nil
  }
}
