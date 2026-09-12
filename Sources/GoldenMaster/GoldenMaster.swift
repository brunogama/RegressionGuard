import Foundation

/// Characterization testing: instead of hand-writing assertions about what a piece of code should
/// do, you record what it actually does once, commit that recording, and fail the build if the
/// behavior ever silently drifts from it.
///
/// ```swift
/// @Test func rendersInvoiceHTML() throws {
///     let html = InvoiceRenderer().render(sampleInvoice)
///     try Characterization.verify(html)
/// }
/// ```
///
/// Snapshots are written next to the calling test file, under `__GoldenMasters__/`, so reviewers
/// see behavior changes as an ordinary diff in the PR. Set `GM_RECORD=1` in the environment to
/// record every snapshot hit during the run instead of comparing against it.
public enum Characterization {

  /// Directory name created alongside each test file that records snapshots.
  public static var directoryName = "__GoldenMasters__"

  /// Verify or record a snapshot for an arbitrary `CharacterizationSnapshottable` value.
  ///
  /// - Parameters:
  ///   - value: The value under test.
  ///   - identifier: Use when a single test records more than one snapshot.
  ///   - testName: Defaults to the enclosing function; rarely needs overriding.
  ///   - file: Defaults to the calling file; determines where the snapshot is stored.
  /// - Throws: `CharacterizationMismatch` if the value differs from the recorded snapshot, or
  ///   `CharacterizationMissing` if no snapshot has been recorded and `GM_RECORD` is not set.
  public static func verify(
    _ value: some CharacterizationSnapshottable,
    identifier: String? = nil,
    testName: String = #function,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let actual = normalize(value.characterizationSnapshot())
    let url = snapshotURL(forFile: file, testName: testName, identifier: identifier)

    if isRecording {
      try record(actual, to: url)
      return
    }

    guard let recorded = try? String(contentsOf: url, encoding: .utf8) else {
      if allowMissingAsRecord {
        try record(actual, to: url)
        return
      }
      throw CharacterizationMissing(testName: testName, snapshotPath: url.path)
    }

    let expected = normalize(recorded)
    if expected != actual {
      throw CharacterizationMismatch(
        testName: testName,
        snapshotPath: url.path,
        expected: expected,
        actual: actual
      )
    }
  }

  /// Convenience overload for raw strings.
  public static func verify(
    _ value: String,
    identifier: String? = nil,
    testName: String = #function,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try verify(
      StringSnapshot(value),
      identifier: identifier,
      testName: testName,
      file: file,
      line: line
    )
  }

  /// Convenience overload for any `Encodable` value.
  public static func verify<T: Encodable>(
    _ value: T,
    identifier: String? = nil,
    testName: String = #function,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try verify(
      AnyEncodableSnapshot(value),
      identifier: identifier,
      testName: testName,
      file: file,
      line: line
    )
  }

  // MARK: - Environment

  /// `GM_RECORD=1` or `true` forces every `verify` call to overwrite its snapshot.
  public static var isRecording: Bool {
    flagIsSet(ProcessInfo.processInfo.environment["GM_RECORD"])
  }

  /// `GM_RECORD_MISSING=1` records automatically the first time a snapshot does not exist yet.
  public static var allowMissingAsRecord: Bool {
    flagIsSet(ProcessInfo.processInfo.environment["GM_RECORD_MISSING"])
  }

  private static func flagIsSet(_ raw: String?) -> Bool {
    guard let raw else { return false }
    return ["1", "true", "yes"].contains(raw.lowercased())
  }

  // MARK: - Storage

  private static func snapshotURL(
    forFile file: StaticString,
    testName: String,
    identifier: String?
  ) -> URL {
    let fileURL = URL(fileURLWithPath: file.description)
    let directory = fileURL.deletingLastPathComponent().appendingPathComponent(directoryName)
    let baseName = sanitize(testName) + (identifier.map { "_" + sanitize($0) } ?? "")
    return directory.appendingPathComponent(baseName + ".snapshot.txt")
  }

  private static func record(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func normalize(_ string: String) -> String {
    var result = string.replacingOccurrences(of: "\r\n", with: "\n")
    if result.hasSuffix("\n") {
      result.removeLast()
    }
    return result
  }

  private static func sanitize(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
  }
}

private struct StringSnapshot: CharacterizationSnapshottable {
  let value: String
  init(_ value: String) { self.value = value }
  func characterizationSnapshot() -> String { value }
}
