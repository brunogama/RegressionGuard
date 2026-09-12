import Foundation

/// Flags a function whose real body the change replaced with a trap or a constant.
///
/// Genuinely distinct from `behavior_deletion`, which counts the branches a file lost. Stubbing
/// can leave that count unchanged or even raise it, and the shape here is sharper than a count:
/// one named function that used to compute something and now cannot. The signature survives, so
/// every caller still compiles and the type checker reports nothing.
///
/// Requires both trees. A stub is only a regression relative to what was there before: the same
/// `fatalError` in a function the change *added* is an honest unimplemented requirement, and
/// `required init?(coder:)` is the archetype. Reading head alone would flag every one of those.
///
/// Advisory by default, as every new family is. Its benign cases are real - a protocol
/// requirement a type genuinely cannot serve, a deliberate trap on an unreachable path - and
/// telling those from a shortcut needs the reviewer, not the parser.
public struct ImplementationStubbedRule: SyntaxAwareRule {
  public static let ruleID = "implementation_stubbed"
  public static let defaultSeverity = Severity.warning

  /// Calls that end the program rather than produce a value.
  private static let traps: Set<String> = [
    "fatalError", "preconditionFailure", "notImplemented", "unimplemented",
  ]

  /// What a value can be built from and still count as computed rather than constant.
  private static let runtimeValueKinds: Set<SyntaxNodeKind> = [
    .declReferenceExpr, .memberAccessExpr, .functionCallExpr, .macroExpansionExpr,
    .closureExpr, .forceUnwrapExpr, .optionalChainingExpr, .tryExpr, .infixOperatorExpr,
  ]

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
    guard !context.pathClassifier.isTestPath(fileDiff.displayPath) else { return [] }
    guard let base = syntax.baseTree, let head = syntax.headTree else { return [] }
    let severity = Self.settings(from: context).severity
    let map = fileDiff.changedLineMap

    // An overload set shares a name, so a name is only treated as previously implemented when no
    // member of the set was already a stub. That keeps a set containing one honest trap from
    // making every sibling look newly stubbed.
    let wasImplemented = Self.implementationStateByName(in: base)

    return head.nodes(ofKind: .functionDecl)
      .filter { map.touches($0.span, at: .head) }
      .filter { Self.isStubbed($0) }
      .filter { $0.name.flatMap { wasImplemented[$0] } == true }
      .map { function in
        Violation(
          ruleID: Self.ruleID,
          severity: severity,
          file: syntax.path,
          line: map.reportLine(for: function.span, at: .head),
          message: "Function body was replaced by a stub instead of implemented.",
          detail: "`" + (function.name ?? "function")
            + "` no longer computes anything its callers can depend on."
        )
      }
  }

  /// Which names had a body doing real work, keyed by function name.
  private static func implementationStateByName(in tree: SyntaxTree) -> [String: Bool] {
    Dictionary(
      tree.nodes(ofKind: .functionDecl).compactMap { function in
        function.name.map { ($0, !isStubbed(function)) }
      },
      uniquingKeysWith: { $0 && $1 }
    )
  }

  /// - Returns: `true` when the body is a single trap or a single constant return.
  ///
  /// Read through `bodyStatements` rather than the block's children, so a projection that keeps
  /// swift-syntax's statement list as a node of its own does not make every body look like one
  /// opaque statement - which would read as "not stubbed" for every function in the file.
  private static func isStubbed(_ function: SyntaxNode) -> Bool {
    let statements = function.bodyStatements
    guard statements.count == 1, let only = statements.first else { return false }
    if traps.contains(only.name ?? "") { return true }
    guard only.kind == .returnStmt else { return false }
    return !only.selfAndDescendants.contains { runtimeValueKinds.contains($0.kind) }
  }
}
