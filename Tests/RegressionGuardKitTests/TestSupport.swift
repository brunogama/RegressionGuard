import Foundation
@testable import RegressionGuardKit

/// Shared helpers for constructing rule test fixtures without needing a real git repository.
enum TestSupport {

  static func context(
    configuration: Configuration = .default,
    commitMessages: [String] = []
  ) -> RuleContext {
    let classifier = PathClassifier(
      testPatterns: configuration.testPaths,
      ignorePatterns: configuration.ignore
    )
    let repository = GitRepository(workingDirectory: FileManager.default.temporaryDirectory)
    return RuleContext(
      configuration: configuration,
      pathClassifier: classifier,
      repository: repository,
      baseRef: "base",
      headRef: "head",
      commitMessages: commitMessages
    )
  }

  /// Builds a single-hunk `FileDiff` from parallel arrays of removed/added lines (line numbers
  /// are synthesized starting at 1; tests care about content, not exact numbering).
  static func fileDiff(
    path: String,
    removed: [String] = [],
    added: [String] = [],
    isDeleted: Bool = false,
    isAdded: Bool = false
  ) -> FileDiff {
    var lines: [DiffLine] = []
    for (index, text) in removed.enumerated() {
      lines.append(DiffLine(kind: .removed, number: index + 1, text: text))
    }
    for (index, text) in added.enumerated() {
      lines.append(DiffLine(kind: .added, number: index + 1, text: text))
    }
    let hunk = Hunk(oldStart: 1, newStart: 1, lines: lines)
    return FileDiff(
      oldPath: isAdded ? nil : path,
      newPath: isDeleted ? nil : path,
      isDeleted: isDeleted,
      isAdded: isAdded,
      isRenamed: false,
      hunks: [hunk]
    )
  }
}
