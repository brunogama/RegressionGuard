import Foundation

/// Thrown when a recorded snapshot does not match the current output.
public struct CharacterizationMismatch: Error, CustomStringConvertible {
  public let testName: String
  public let snapshotPath: String
  public let expected: String
  public let actual: String

  public var description: String {
    """
    Characterization snapshot mismatch for "\(testName)"
    snapshot: \(snapshotPath)

    --- expected (recorded) ---
    \(expected)

    --- actual (current run) ---
    \(actual)

    If this change is intentional, re-run with GM_RECORD=1 to update the recorded snapshot,
    then review the diff of the snapshot file itself in your PR.
    """
  }
}

/// Thrown when no snapshot has ever been recorded for a given test.
public struct CharacterizationMissing: Error, CustomStringConvertible {
  public let testName: String
  public let snapshotPath: String

  public var description: String {
    """
    No characterization snapshot found for "\(testName)".
    Expected one at: \(snapshotPath)
    Run with GM_RECORD=1 to record the current output as the new baseline.
    """
  }
}
