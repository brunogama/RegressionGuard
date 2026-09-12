import Foundation

/// How base source is read out of the repository.
///
/// The whole point of the harness: these two do identical work and differ only in how many times
/// they spawn, which is what the budget's first clause is written about.
public enum FetchStrategy: String, CaseIterable, Sendable {
  /// One `git show <ref>:<path>` per file - what `GitRepository.show` does today.
  case perFile = "per-file"
  /// One `git cat-file --batch` fed every path at once.
  case batched

  /// Reads `paths` at `ref`, keyed by path.
  public func sources(for paths: [String], repo: String, ref: String) -> [String: String] {
    switch self {
    case .perFile: Self.perFileSources(paths, repo: repo, ref: ref)
    case .batched: Self.batchedSources(paths, repo: repo, ref: ref)
    }
  }

  private static func perFileSources(
    _ paths: [String],
    repo: String,
    ref: String
  ) -> [String: String] {
    var sources: [String: String] = [:]
    for path in paths {
      sources[path] = String(
        decoding: GitCommand.run(["show", "\(ref):\(path)"], in: repo),
        as: UTF8.self
      )
    }
    return sources
  }

  /// One `git cat-file --batch` for the whole file set.
  ///
  /// The object specs go in on stdin and the replies come back framed by a `<sha> blob <size>`
  /// header, so the contents are split on the declared byte counts rather than on anything in the
  /// source text - which could itself contain a line that looks like a header.
  private static func batchedSources(
    _ paths: [String],
    repo: String,
    ref: String
  ) -> [String: String] {
    guard !paths.isEmpty else { return [:] }

    let specs = paths.map { "\(ref):\($0)" }.joined(separator: "\n") + "\n"
    let data = GitCommand.run(["cat-file", "--batch"], in: repo, stdin: Data(specs.utf8))

    var sources: [String: String] = [:]
    var cursor = data.startIndex
    for path in paths {
      guard let newline = data[cursor...].firstIndex(of: UInt8(ascii: "\n")) else { break }
      let header = String(decoding: data[cursor..<newline], as: UTF8.self)
      cursor = data.index(after: newline)
      let parts = header.split(separator: " ")
      guard parts.count == 3, let size = Int(parts[2]) else { continue }
      let end = data.index(cursor, offsetBy: size)
      sources[path] = String(decoding: data[cursor..<end], as: UTF8.self)
      cursor = data.index(end, offsetBy: 1)  // trailing newline the framing adds
    }
    return sources
  }
}
