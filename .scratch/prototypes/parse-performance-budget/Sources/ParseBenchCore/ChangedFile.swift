import Foundation

/// One Swift file in a diff, and which sides of it exist.
///
/// The two flags are what decide how many parses a file costs: a modified file is parsed twice,
/// an added or deleted one only once.
public struct ChangedFile: Sendable {
  public var path: String
  public var existsInBase: Bool
  public var existsInHead: Bool

  public init(path: String, existsInBase: Bool, existsInHead: Bool) {
    self.path = path
    self.existsInBase = existsInBase
    self.existsInHead = existsInHead
  }

  /// The Swift files a rule could ask about in `base..head`.
  ///
  /// Read from a real diff rather than a glob, because the worst case the budget cares about is a
  /// large refactor's file list. `--no-renames` is deliberate: a rename read as one path would
  /// hide that both sides have to be fetched and parsed.
  public static func inDiff(repo: String, base: String, head: String) -> [ChangedFile] {
    let raw = GitCommand.run(
      ["diff", "--name-status", "--no-renames", "\(base)..\(head)", "--", "*.swift"],
      in: repo
    )
    return String(decoding: raw, as: UTF8.self).split(separator: "\n").compactMap { line in
      let fields = line.split(separator: "\t", maxSplits: 1)
      guard fields.count == 2 else { return nil }
      let path = String(fields[1])
      switch fields[0].first {
      case "A": return ChangedFile(path: path, existsInBase: false, existsInHead: true)
      case "D": return ChangedFile(path: path, existsInBase: true, existsInHead: false)
      default: return ChangedFile(path: path, existsInBase: true, existsInHead: true)
      }
    }
  }
}
