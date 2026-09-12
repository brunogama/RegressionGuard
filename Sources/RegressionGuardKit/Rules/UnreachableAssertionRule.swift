import Foundation

/// Flags an assertion the change put somewhere it cannot run.
///
/// The same harm `weakened_assertion` exists to catch - an assertion that no longer constrains
/// the code under test - reached by a different route. It is a separate rule ID rather than a
/// detection inside that family because the confidence is lower: `weakened_assertion` decides a
/// question about a call's own arguments and blocks on the answer, while reachability is
/// undecidable from syntax and this rule only ever sees a suggestive shape. Inheriting a blocking
/// severity for a heuristic is how a guard earns the right to be switched off.
///
/// Two cases, both provable without semantics:
///
/// - An assertion inside a block guarded by a literal `false`.
/// - An assertion sitting after an unconditional exit in the same block, where nothing between
///   them can resume execution.
///
/// Deliberately not claimed: a condition that is constant only after inlining, a loop that never
/// iterates, an `#if` branch excluded by build flags. Those need a compiler.
public struct UnreachableAssertionRule: SyntaxAwareRule {
  public static let ruleID = "unreachable_assertion"
  public static let defaultSeverity = Severity.warning

  /// Statements after which nothing in the same block runs.
  private static let unconditionalExits: Set<SyntaxNodeKind> = [.returnStmt, .throwStmt]

  /// Calls that end the program, which are exits written as calls rather than statements.
  private static let trapCalls: Set<String> = ["fatalError", "preconditionFailure"]

  private static let blockKinds: Set<SyntaxNodeKind> = [.codeBlock, .closureExpr]

  public init() {}

  public func syntacticEvidenceRequests(for fileDiff: FileDiff) -> [SyntacticEvidenceRequest] {
    guard fileDiff.isSwiftSource else { return [] }
    return [SyntacticEvidenceRequest(fileDiff: fileDiff)]
  }

  public func diffViolations(fileDiff: FileDiff, context: RuleContext) async -> [Violation] {
    []
  }

  public func textFallbackViolations(
    fileDiff: FileDiff,
    context: RuleContext
  ) async -> [Violation] {
    []
  }

  public func syntacticViolations(
    fileDiff: FileDiff,
    syntax: SyntacticFileEvidence,
    context: RuleContext
  ) -> [Violation] {
    guard context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    guard let head = syntax.headTree else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap

    let unreachable =
      Self.assertionsUnderFalseCondition(in: head) + Self.assertionsAfterExit(in: head)

    return
      unreachable
      // The change has to have reached the construct that made the assertion unreachable, not
      // merely the file. An assertion that was already stranded is somebody else's finding.
      .filter { map.touches($0.cause.span, at: .head) || map.touches($0.assertion.span, at: .head) }
      .map { finding in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: syntax.path,
          line: map.reportLine(for: finding.assertion.span, at: .head),
          message: "Assertion cannot run, so it no longer checks anything.",
          detail: finding.reason
        )
      }
  }

  /// One stranded assertion: the call, and the syntax that stranded it.
  private struct Stranded {
    let assertion: SyntaxNode
    let cause: SyntaxNode
    let reason: String
  }

  private static func assertionsUnderFalseCondition(in tree: SyntaxTree) -> [Stranded] {
    tree.nodes(ofKind: .ifExpr).flatMap { branch -> [Stranded] in
      // The condition is everything before the first block, searched through its whole subtree:
      // swift-syntax nests a condition as `ConditionElementList` -> `ConditionElement` -> the
      // expression, so reading the branch's direct children would find no literal under a
      // faithful projection and switch this half of the rule off without a test going red.
      let children = branch.children
      let bodyIndex = children.firstIndex { blockKinds.contains($0.kind) } ?? children.endIndex
      let condition = children[children.startIndex..<bodyIndex]
      guard condition.contains(where: { $0.containsNode(ofAnyKind: [.booleanLiteralExpr]) }),
        condition.contains(where: { isFalseLiteral(in: $0) })
      else { return [] }

      // Only the then-block. The `else` of an `if false` is the one branch that always runs, so
      // sweeping the whole subtree would flag the only reachable code in it.
      guard bodyIndex < children.endIndex else { return [] }
      return children[bodyIndex].selfAndDescendants.filter(AssertionCall.isAssertion).map {
        Stranded(
          assertion: $0,
          cause: branch,
          reason: "The branch holding this assertion is written `if false`."
        )
      }
    }
  }

  /// Whether `node`'s subtree holds a `false` literal.
  ///
  /// Reads the spelling off `name`, which is the only carrier the projection has for it. A
  /// projector that leaves a literal's `name` nil makes `if false` and `if true` indistinguishable
  /// here, and this detection finds nothing - recorded as the one projection obligation the rule
  /// could not absorb.
  private static func isFalseLiteral(in node: SyntaxNode) -> Bool {
    node.selfAndDescendants.contains { $0.kind == .booleanLiteralExpr && $0.name == "false" }
  }

  private static func assertionsAfterExit(in tree: SyntaxTree) -> [Stranded] {
    tree.nodes(ofAnyKind: blockKinds).flatMap { block -> [Stranded] in
      // `statements`, not `children`: a projection that keeps swift-syntax's statement list as a
      // node would otherwise hand back one child, and no block would ever appear to hold an exit.
      let statements = block.statements
      guard let exitIndex = statements.firstIndex(where: isUnconditionalExit) else {
        return []
      }
      let exit = statements[exitIndex]
      return statements.dropFirst(exitIndex + 1)
        .filter { AssertionCall.isAssertion($0) }
        .map {
          Stranded(
            assertion: $0,
            cause: exit,
            reason: "Execution leaves this block at line \(exit.span.start), before the assertion."
          )
        }
    }
  }

  private static func isUnconditionalExit(_ node: SyntaxNode) -> Bool {
    unconditionalExits.contains(node.kind) || trapCalls.contains(node.name ?? "")
  }
}
