import Foundation

/// Which side of the comparison a tree was read from.
public enum SyntaxRef: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case base
  case head
}

/// Why a file legitimately has no source at one ref.
///
/// Distinct from `SyntaxEvidenceGap`: nothing failed here, the file simply does not exist on that
/// side, and a rule can reason about that with full confidence.
public enum SyntaxSourceAbsence: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  /// The file is new, so there is no base-ref source.
  case fileAdded
  /// The file was deleted, so there is no head-ref source.
  case fileDeleted
}

/// Why source that should have existed could not be turned into a tree.
///
/// Every case here is a gap a rule must degrade around, and the run has to report it. None of
/// them may be read as "nothing to find".
public enum SyntaxEvidenceGapReason: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  /// No parser was supplied to the run, so no file could be parsed. A binary-distributed
  /// RegressionGuardKit reaches rules this way.
  case parserUnavailable
  /// Reading the source at this ref failed, for example an unreachable base ref.
  case sourceReadFailed
  /// The source was read but could not be decoded as text.
  case sourceNotDecodable
  /// The provider was asked for this file and returned nothing for it. A dropped request is a
  /// gap: left unreconciled it would be indistinguishable from a file no rule ever asked about,
  /// which is the one reading that turns a would-be finding into a pass.
  case requestUnanswered
}

/// One explicit, reportable hole in the syntactic evidence for a run.
public struct SyntaxEvidenceGap: Codable, Equatable, Hashable, Sendable {
  public let path: String
  public let ref: SyntaxRef
  public let reason: SyntaxEvidenceGapReason
  /// Free-form context for a human reading the report, such as the failing git invocation.
  public let detail: String?

  public init(path: String, ref: SyntaxRef, reason: SyntaxEvidenceGapReason, detail: String? = nil)
  {
    self.path = path
    self.ref = ref
    self.reason = reason
    self.detail = detail
  }
}

/// What a rule gets for one file at one ref.
///
/// Three outcomes, all explicit. There is no `nil` tree, because an optional would let a gap read
/// as an absence and quietly turn a would-be finding into a pass.
public enum SyntaxTreeAvailability: Codable, Equatable, Sendable {
  /// A tree was produced. Error-tolerant parsing means this holds for ill-formed source too;
  /// check `SyntaxTree.hasParseErrors` for that.
  case parsed(SyntaxTree)
  /// The file has no source at this ref, and that is the expected state.
  case absent(SyntaxSourceAbsence)
  /// Source should have existed but is missing. A rule must degrade explicitly.
  case unavailable(SyntaxEvidenceGapReason, detail: String?)

  public var tree: SyntaxTree? {
    guard case .parsed(let tree) = self else { return nil }
    return tree
  }

  /// `true` when a rule must fall back to line-based detection for this side.
  public var isGap: Bool {
    if case .unavailable = self { return true }
    return false
  }
}

/// Base and head trees for one changed file, paired.
///
/// Always a pair: swift-syntax has no tree-diff API, so every base-versus-head judgement is built
/// by a rule from both sides, and a rule that only saw head could not tell a deletion from an
/// absence.
public struct SyntacticFileEvidence: Codable, Equatable, Sendable {
  /// The path a finding is reported against, matching `FileDiff.displayPath`.
  public let path: String
  public let base: SyntaxTreeAvailability
  public let head: SyntaxTreeAvailability

  public init(path: String, base: SyntaxTreeAvailability, head: SyntaxTreeAvailability) {
    self.path = path
    self.base = base
    self.head = head
  }

  public var baseTree: SyntaxTree? { base.tree }
  public var headTree: SyntaxTree? { head.tree }

  /// `true` when either side is a gap, so a rule must degrade to line-based detection and the run
  /// must report why.
  public var isDegraded: Bool { base.isGap || head.isGap }

  public var gaps: [SyntaxEvidenceGap] {
    [(SyntaxRef.base, base), (SyntaxRef.head, head)].compactMap { ref, availability in
      guard case .unavailable(let reason, let detail) = availability else { return nil }
      return SyntaxEvidenceGap(path: path, ref: ref, reason: reason, detail: detail)
    }
  }
}

/// The syntactic evidence resolved for one run: parsed files, keyed by reported path.
///
/// A path that is absent from `files` was never requested, which is a different thing from a
/// requested file whose trees came back unavailable. Rules read through `evidence(for:)` so the
/// two cannot be confused.
public struct SyntacticEvidence: Codable, Equatable, Sendable {
  public static let none = Self(files: [])

  private let filesByPath: [String: SyntacticFileEvidence]

  public init(files: [SyntacticFileEvidence]) {
    filesByPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
  }

  public var files: [SyntacticFileEvidence] {
    filesByPath.values.sorted { $0.path < $1.path }
  }

  public var isEmpty: Bool { filesByPath.isEmpty }

  /// - Returns: the paired trees for `path`, or `nil` when no rule asked for that file.
  public func evidence(for path: String) -> SyntacticFileEvidence? { filesByPath[path] }

  /// - Returns: the paired trees for `fileDiff`, or `nil` when no rule asked for that file.
  public func evidence(for fileDiff: FileDiff) -> SyntacticFileEvidence? {
    evidence(for: fileDiff.displayPath)
  }

  /// Every gap in the run, in a stable order, for the run to report.
  public var gaps: [SyntaxEvidenceGap] {
    files.flatMap(\.gaps)
  }

  /// Fills in every request the provider left unanswered, as an explicit gap.
  ///
  /// A run only trusts what it can account for. Without this, a provider that quietly dropped a
  /// file would leave that path missing from `files`, which reads as "no rule asked for it" and
  /// turns a would-be finding into a pass.
  public func reconciled(with requests: [SyntacticEvidenceRequest]) -> Self {
    let unanswered = requests.filter { filesByPath[$0.path] == nil }
    guard !unanswered.isEmpty else { return self }
    return Self(
      files: files
        + unanswered.map {
          $0.unavailableEvidence(
            reason: .requestUnanswered,
            detail: "The syntactic evidence provider returned no result for this file."
          )
        }
    )
  }

  public func retainingPaths(_ paths: Set<String>) -> Self {
    Self(files: files.filter { paths.contains($0.path) })
  }
}

/// One file a rule asked to have parsed.
///
/// The requested paths encode the expected absences: a new file has no `basePath`, a deleted file
/// has no `headPath`, and a rename carries a different path on each side.
public struct SyntacticEvidenceRequest: Codable, Equatable, Hashable, Sendable {
  /// The path a finding is reported against, matching `FileDiff.displayPath`.
  public let path: String
  public let basePath: String?
  public let headPath: String?

  public init(path: String, basePath: String?, headPath: String?) {
    self.path = path
    self.basePath = basePath
    self.headPath = headPath
  }

  public init(fileDiff: FileDiff) {
    self.init(
      path: fileDiff.displayPath,
      basePath: fileDiff.isAdded ? nil : fileDiff.oldPath,
      headPath: fileDiff.isDeleted ? nil : fileDiff.newPath
    )
  }

  /// Evidence for this request with no tree on either side that was expected to have one.
  ///
  /// The sides the request already expected to be empty stay absences, so a gap is only ever
  /// claimed for source that should have existed.
  func unavailableEvidence(
    reason: SyntaxEvidenceGapReason,
    detail: String?
  ) -> SyntacticFileEvidence {
    SyntacticFileEvidence(
      path: path,
      base: basePath == nil ? .absent(.fileAdded) : .unavailable(reason, detail: detail),
      head: headPath == nil ? .absent(.fileDeleted) : .unavailable(reason, detail: detail)
    )
  }
}

/// Turns requests into parsed evidence.
///
/// Deliberately batched. Parsing is effectively free at roughly 0.125 ms per file, while reading
/// one file at the base ref costs about 9 ms of subprocess, so a per-file interface would make the
/// subprocess the cost of the whole feature. One call per run, all files at once.
///
/// RegressionGuardKit declares this and never implements it: it has no package dependencies and
/// cannot parse Swift. The CLI owns the parsing target and injects the implementation.
///
/// A provider is built already knowing which refs it reads, so a request names only paths. That
/// keeps the working-tree case - where head is the checkout rather than a ref - expressible
/// without RegressionGuardKit having to model it.
public protocol SyntacticEvidenceProvider: Sendable {
  func syntacticEvidence(for requests: [SyntacticEvidenceRequest]) -> SyntacticEvidence
}

/// The evidence a run gets when no parser was injected: every requested file is an explicit gap.
///
/// Used so a RegressionGuardKit without a parser degrades visibly rather than behaving as though
/// every file were clean.
public struct UnavailableSyntacticEvidenceProvider: SyntacticEvidenceProvider {
  public init() {}

  public func syntacticEvidence(for requests: [SyntacticEvidenceRequest]) -> SyntacticEvidence {
    SyntacticEvidence(
      files: requests.map {
        $0.unavailableEvidence(
          reason: .parserUnavailable,
          detail: "No Swift parser was supplied to this run."
        )
      }
    )
  }
}
