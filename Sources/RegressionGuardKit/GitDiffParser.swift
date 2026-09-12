import Foundation

public struct DiffLine: Codable, Equatable, Sendable {
  public enum Kind: Codable, Equatable, Sendable {
    case added
    case removed
    case context
  }
  public let kind: Kind
  public let number: Int
  public let text: String

  public init(kind: Kind, number: Int, text: String) {
    self.kind = kind
    self.number = number
    self.text = text
  }
}

public struct Hunk: Codable, Equatable, Sendable {
  public let oldStart: Int
  public let newStart: Int
  public let lines: [DiffLine]

  public init(oldStart: Int, newStart: Int, lines: [DiffLine]) {
    self.oldStart = oldStart
    self.newStart = newStart
    self.lines = lines
  }

  public var addedLines: [DiffLine] { lines.filter { $0.kind == .added } }
  public var removedLines: [DiffLine] { lines.filter { $0.kind == .removed } }
}

public struct FileDiff: Codable, Equatable, Sendable {
  public let oldPath: String?
  public let newPath: String?
  public let isDeleted: Bool
  public let isAdded: Bool
  public let isRenamed: Bool
  public let hunks: [Hunk]

  public init(
    oldPath: String?,
    newPath: String?,
    isDeleted: Bool,
    isAdded: Bool,
    isRenamed: Bool,
    hunks: [Hunk]
  ) {
    self.oldPath = oldPath
    self.newPath = newPath
    self.isDeleted = isDeleted
    self.isAdded = isAdded
    self.isRenamed = isRenamed
    self.hunks = hunks
  }

  /// The path to report to the user: the new path unless the file was deleted.
  public var displayPath: String { newPath ?? oldPath ?? "<unknown>" }

  public var addedLines: [DiffLine] { hunks.flatMap { $0.addedLines } }
  public var removedLines: [DiffLine] { hunks.flatMap { $0.removedLines } }

  /// `true` when this file is Swift source, and so can carry syntactic evidence.
  public var isSwiftSource: Bool { displayPath.hasSuffix(".swift") }
}

/// Parses the output of `git diff --no-color -U<n>` into structured `FileDiff` values.
/// This small hand-rolled parser avoids a SwiftSyntax or regex dependency.
public struct GitDiffParser {

  public init() {}

  public func parse(_ raw: String) -> [FileDiff] {
    let lines = raw.components(separatedBy: "\n")
    var files: [FileDiff] = []
    var index = 0

    while index < lines.count {
      if let file = Self.parseFile(in: lines, from: &index) {
        files.append(file)
      } else {
        index += 1
      }
    }

    return files
  }

  private static func parseFile(in lines: [String], from index: inout Int) -> FileDiff? {
    guard lines[index].hasPrefix("diff --git ") else { return nil }
    index += 1

    let header = parseHeader(in: lines, from: &index)
    let hunks = parseHunks(in: lines, from: &index)
    let cleanedOld = cleanedPath(header.oldPath)
    let cleanedNew = cleanedPath(header.newPath)

    return FileDiff(
      oldPath: cleanedOld,
      newPath: cleanedNew,
      isDeleted: header.isDeleted || cleanedNew == nil,
      isAdded: header.isAdded || cleanedOld == nil,
      isRenamed: header.isRenamed,
      hunks: hunks
    )
  }

  private static func parseHeader(
    in lines: [String],
    from index: inout Int
  ) -> DiffHeader {
    var header = DiffHeader()

    while index < lines.count {
      let line = lines[index]
      guard !line.hasPrefix("diff --git "), !line.hasPrefix("@@") else { break }
      header.apply(line)
      index += 1
    }

    return header
  }

  private static func parseHunks(in lines: [String], from index: inout Int) -> [Hunk] {
    var hunks: [Hunk] = []

    while index < lines.count, lines[index].hasPrefix("@@") {
      guard let starts = parseHunkHeader(lines[index]) else { break }
      index += 1
      hunks.append(parseHunkLines(in: lines, from: &index, starts: starts))
    }

    return hunks
  }

  private static func parseHunkLines(
    in lines: [String],
    from index: inout Int,
    starts: HunkStart
  ) -> Hunk {
    var oldLine = starts.old
    var newLine = starts.new
    var hunkLines: [DiffLine] = []

    while index < lines.count, isHunkBodyLine(lines[index]) {
      appendLine(lines[index], oldLine: &oldLine, newLine: &newLine, into: &hunkLines)
      index += 1
    }

    return Hunk(oldStart: starts.old, newStart: starts.new, lines: hunkLines)
  }

  private static func appendLine(
    _ raw: String,
    oldLine: inout Int,
    newLine: inout Int,
    into lines: inout [DiffLine]
  ) {
    if raw.hasPrefix("+") && !raw.hasPrefix("+++") {
      lines.append(DiffLine(kind: .added, number: newLine, text: String(raw.dropFirst())))
      newLine += 1
    } else if raw.hasPrefix("-") && !raw.hasPrefix("---") {
      lines.append(DiffLine(kind: .removed, number: oldLine, text: String(raw.dropFirst())))
      oldLine += 1
    } else if !raw.hasPrefix("\\ No newline") {
      appendContextLine(raw, oldLine: &oldLine, newLine: &newLine, into: &lines)
    }
  }

  private static func appendContextLine(
    _ raw: String,
    oldLine: inout Int,
    newLine: inout Int,
    into lines: inout [DiffLine]
  ) {
    let text = raw.isEmpty ? "" : String(raw.dropFirst())
    lines.append(DiffLine(kind: .context, number: newLine, text: text))
    oldLine += 1
    newLine += 1
  }

  private static func isHunkBodyLine(_ line: String) -> Bool {
    !line.hasPrefix("@@") && !line.hasPrefix("diff --git ")
  }

  private static func cleanedPath(_ path: String?) -> String? {
    path.flatMap { $0 == "/dev/null" ? nil : stripAB($0) }
  }

  fileprivate static func stripPrefix(_ line: String, _ prefix: String) -> String {
    String(line.dropFirst(prefix.count))
  }

  /// `a/Sources/Foo.swift` -> `Sources/Foo.swift`
  private static func stripAB(_ path: String) -> String {
    if path.hasPrefix("a/") || path.hasPrefix("b/") {
      return String(path.dropFirst(2))
    }
    return path
  }

  /// Parses `@@ -12,7 +12,9 @@ optional context` into start line numbers.
  private static func parseHunkHeader(_ line: String) -> HunkStart? {
    let parts = line.split(separator: " ")
    guard parts.count >= 3 else { return nil }
    guard let oldRange = parts.first(where: { $0.hasPrefix("-") }) else { return nil }
    guard let newRange = parts.first(where: { $0.hasPrefix("+") }) else { return nil }
    let old = Int(oldRange.dropFirst().split(separator: ",").first ?? "0") ?? 0
    let new = Int(newRange.dropFirst().split(separator: ",").first ?? "0") ?? 0
    return HunkStart(old: old, new: new)
  }
}

private struct DiffHeader {
  var oldPath: String?
  var newPath: String?
  var isDeleted = false
  var isAdded = false
  var isRenamed = false

  mutating func apply(_ line: String) {
    if line.hasPrefix("--- ") {
      oldPath = GitDiffParser.stripPrefix(line, "--- ")
    } else if line.hasPrefix("+++ ") {
      newPath = GitDiffParser.stripPrefix(line, "+++ ")
    } else if line.hasPrefix("deleted file mode") {
      isDeleted = true
    } else if line.hasPrefix("new file mode") {
      isAdded = true
    } else if line.hasPrefix("rename from") || line.hasPrefix("rename to") {
      isRenamed = true
    }
  }
}

private struct HunkStart {
  let old: Int
  let new: Int
}
