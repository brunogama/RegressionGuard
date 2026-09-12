import Foundation

public extension FileDiff {
  /// The lines this change touched on each side, and the translation between them.
  var changedLineMap: ChangedLineMap { ChangedLineMap(fileDiff: self) }
}
