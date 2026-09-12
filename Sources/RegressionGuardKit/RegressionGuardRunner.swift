import Foundation

/// The single entry point the CLI and SwiftPM plugin call: loads config, diffs the repo,
/// runs every rule, and returns the collected violations.
public struct RegressionGuardRunner {
  public let repositoryDirectory: URL

  public init(repositoryDirectory: URL) {
    self.repositoryDirectory = repositoryDirectory
  }

  /// - Parameters:
  ///   - base: the ref to compare against, such as `origin/main` or a merge-base SHA.
  ///   - head: the ref to check, or `nil` to check the working tree.
  public func check(base: String, head: String?) throws -> [Violation] {
    let repository = GitRepository(workingDirectory: repositoryDirectory)
    let configuration = ConfigurationLoader().load(fromDirectory: repositoryDirectory)
    let classifier = PathClassifier(
      testPatterns: configuration.testPaths,
      ignorePatterns: configuration.ignore
    )

    let rawDiff = try repository.diff(base: base, head: head)
    let fileDiffs = GitDiffParser().parse(rawDiff)
    let messages = try commitMessages(repository: repository, base: base, head: head)
    let context = RuleContext(
      configuration: configuration,
      pathClassifier: classifier,
      repository: repository,
      baseRef: base,
      headRef: head ?? "HEAD",
      commitMessages: messages
    )

    return RuleEngine().run(diff: fileDiffs, context: context)
  }

  private func commitMessages(
    repository: GitRepository,
    base: String,
    head: String?
  ) throws -> [String] {
    guard let head else { return [] }
    return try repository.commitMessages(base: base, head: head)
  }
}
