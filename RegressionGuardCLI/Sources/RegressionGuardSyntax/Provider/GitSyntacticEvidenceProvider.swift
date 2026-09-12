import Foundation
import RegressionGuardKit

/// Reads the source a run needs out of git and projects it.
///
/// The half RegressionGuardKit cannot have: it declares `SyntacticEvidenceProvider`, has no
/// dependencies, and cannot parse Swift or spawn git on its own terms. This target holds both.
///
/// Built knowing its refs, so a request names only paths. A `nil` head is the working tree, which
/// is how `regression-guard check --base main` runs with no head ref at all, and is why this is
/// expressible here without RegressionGuardKit having to model a checkout.
public struct GitSyntacticEvidenceProvider: SyntacticEvidenceProvider {
  private let repositoryDirectory: URL
  private let baseRef: String
  /// The ref to read head from, or `nil` to read the working tree.
  private let headRef: String?

  public var grammar: SyntaxGrammar? { CompiledSyntaxGrammar.current }

  public init(repositoryDirectory: URL, baseRef: String, headRef: String?) {
    self.repositoryDirectory = repositoryDirectory
    self.baseRef = baseRef
    self.headRef = headRef
  }

  public func syntacticEvidence(for requests: [SyntacticEvidenceRequest]) -> SyntacticEvidence {
    // Every object the run needs, named once, read in one spawn. The budget for this feature is
    // one subprocess per run rather than a number of milliseconds: a read per file is linear in
    // the file count and was measured at 286x the batch on a 504-file diff.
    var objects: [String] = []
    for request in requests {
      if let basePath = request.basePath { objects.append("\(baseRef):\(basePath)") }
      if let headRef, let headPath = request.headPath { objects.append("\(headRef):\(headPath)") }
    }
    let sources = GitObjectBatch(repositoryDirectory: repositoryDirectory).read(objects)

    return SyntacticEvidence(
      files: requests.map { request in
        SyntacticFileEvidence(
          path: request.path,
          base: availability(of: request.basePath, at: .base, in: sources),
          head: availability(of: request.headPath, at: .head, in: sources)
        )
      }
    )
  }

  /// The three outcomes, kept apart.
  ///
  /// A side the request never expected is an absence and costs the run nothing. A side that was
  /// expected and could not be read is a gap the run reports. Only source that arrived becomes a
  /// tree. Folding the first two together is the one reading that turns a would-be finding into a
  /// pass.
  private func availability(
    of path: String?,
    at ref: SyntaxRef,
    in sources: [String: Result<Data, GitObjectBatch.Failure>]
  ) -> SyntaxTreeAvailability {
    guard let path else { return .absent(ref == .base ? .fileAdded : .fileDeleted) }
    let read = ref == .head && headRef == nil ? workingTreeSource(path) : sources[key(path, at: ref)]

    switch read {
    case .success(let data):
      guard let source = String(data: data, encoding: .utf8) else {
        return .unavailable(.sourceNotDecodable, detail: "\(path) at \(refName(ref)) is not UTF-8")
      }
      return .parsed(
        SwiftSyntaxProjection.tree(source: source, path: path, ref: refName(ref))
      )
    case .failure(let failure):
      return .unavailable(.sourceReadFailed, detail: "\(path) at \(refName(ref)): \(failure)")
    case nil:
      // The batch was never asked for this object, which is a bug here rather than a repository
      // state. Reported as a gap all the same: a provider that silently returns nothing for a
      // requested file is indistinguishable from a clean file.
      return .unavailable(.sourceReadFailed, detail: "\(path) at \(refName(ref)) was not requested")
    }
  }

  /// Head read from the checkout rather than from a ref, including files not yet committed.
  private func workingTreeSource(_ path: String) -> Result<Data, GitObjectBatch.Failure> {
    // Appended rather than resolved `relativeTo:`, which reads the base as a file unless it was
    // built as a directory URL - and the caller's is whatever `--path` was spelled as.
    let url = repositoryDirectory.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: url) else { return .failure(.missing) }
    return .success(data)
  }

  private func key(_ path: String, at ref: SyntaxRef) -> String {
    "\(ref == .base ? baseRef : headRef ?? "HEAD"):\(path)"
  }

  private func refName(_ ref: SyntaxRef) -> String {
    switch ref {
    case .base: return baseRef
    case .head: return headRef ?? "working-tree"
    }
  }
}
