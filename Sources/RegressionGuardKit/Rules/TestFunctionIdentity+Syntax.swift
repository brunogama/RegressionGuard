import Foundation

/// Reading a file's test functions off its parsed tree instead of off its lines.
///
/// The line-based reader in `TestFunctionIdentity` calls anything after `func ` a declaration, so
/// a `func ` inside a comment or a string declares a function, and it decides a function is a test
/// by looking back up to five non-blank lines for `@Test`, so a long doc comment between the
/// attribute and the declaration hides it. A tree answers both exactly.
extension TestFunctionIdentity {
  /// One declared function, as the tree reports it.
  struct SyntacticFunction {
    let name: String
    let isTest: Bool
    let span: LineSpan
  }

  /// Compares the functions the base and head trees declare.
  ///
  /// - Returns: a finding for every base test function that is gone from head, or that survives
  ///   with its test identity lost.
  static func violations(
    syntax: SyntacticFileEvidence,
    map: ChangedLineMap,
    severity: Severity
  ) -> [Violation] {
    guard let base = syntax.baseTree, let head = syntax.headTree else { return [] }

    // Overloads share a name, so a name maps to a whole overload set rather than one function.
    // The set keeps its test identity as long as any member of it still reads as a test.
    let survivors = functions(in: head)
    let survivesAsTest = Dictionary(
      survivors.map { ($0.name, $0.isTest) },
      uniquingKeysWith: { $0 || $1 }
    )
    var violations: [Violation] = []

    for function in functions(in: base) where function.isTest {
      guard let isStillTest = survivesAsTest[function.name] else {
        violations.append(
          removedViolation(
            function,
            path: syntax.path,
            severity: severity,
            line: map.reportLine(for: function.span, at: .base)
          )
        )
        continue
      }
      guard !isStillTest else { continue }
      let survivor = survivors.first { $0.name == function.name }
      violations.append(
        lostIdentityViolation(
          function,
          path: syntax.path,
          severity: severity,
          line: survivor.flatMap { map.reportLine(for: $0.span, at: .head) }
        )
      )
    }
    return violations
  }

  /// The functions `tree` declares, and whether each one still reads as a test.
  ///
  /// A function is a test when it is named for one or carries `@Test`. The attribute is read off
  /// the declaration itself, so no line-distance guess is involved.
  static func functions(in tree: SyntaxTree) -> [SyntacticFunction] {
    tree.nodes(ofKind: .functionDecl).compactMap { node in
      guard let name = node.name else { return nil }
      let isTest = name.lowercased().hasPrefix("test") || node.hasAttribute(named: "Test")
      return SyntacticFunction(name: name, isTest: isTest, span: node.span)
    }
  }

  private static func removedViolation(
    _ function: SyntacticFunction,
    path: String,
    severity: Severity,
    line: Int?
  ) -> Violation {
    Violation(
      ruleID: DisabledOrSkippedTestRule.ruleID,
      severity: severity,
      file: path,
      line: line,
      message: "Test function `\(function.name)` was removed rather than fixed.",
      detail: nil
    )
  }

  private static func lostIdentityViolation(
    _ function: SyntacticFunction,
    path: String,
    severity: Severity,
    line: Int?
  ) -> Violation {
    Violation(
      ruleID: DisabledOrSkippedTestRule.ruleID,
      severity: severity,
      file: path,
      line: line,
      message: "Test function `\(function.name)` lost its test identity.",
      detail: "A removed `test...` name or `@Test` attribute can hide a failing test."
    )
  }
}
