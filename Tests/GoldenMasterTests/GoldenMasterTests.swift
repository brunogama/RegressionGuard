import XCTest
@testable import GoldenMaster

final class CharacterizationTests: XCTestCase {

  override func setUpWithError() throws {
    setenv("GM_RECORD", "", 1)
    unsetenv("GM_RECORD")
  }

  func testRecordsThenVerifiesAMatchingSnapshot() throws {
    setenv("GM_RECORD", "1", 1)
    try Characterization.verify("hello world", identifier: "record")
    unsetenv("GM_RECORD")

    try Characterization.verify("hello world", identifier: "record")
  }

  func testMismatchThrows() throws {
    setenv("GM_RECORD", "1", 1)
    try Characterization.verify("version one", identifier: "mismatch")
    unsetenv("GM_RECORD")

    XCTAssertThrowsError(
      try Characterization.verify("version two", identifier: "mismatch")
    ) { error in
      XCTAssertTrue(error is CharacterizationMismatch)
    }
  }

  func testMissingSnapshotThrowsByDefault() throws {
    // Use a unique identifier so a previous run's recording can't mask this failing.
    let identifier = "missing-\(UUID().uuidString)"
    XCTAssertThrowsError(
      try Characterization.verify("anything", identifier: identifier)
    ) { error in
      XCTAssertTrue(error is CharacterizationMissing)
    }
  }

  struct SampleInvoice: Encodable {
    let id: Int
    let total: Double
  }

  func testEncodableSnapshotRecordsStableJSON() throws {
    setenv("GM_RECORD", "1", 1)
    try Characterization.verify(
      SampleInvoice(id: 1, total: 42.5),
      identifier: "invoice"
    )
    unsetenv("GM_RECORD")

    try Characterization.verify(
      SampleInvoice(id: 1, total: 42.5),
      identifier: "invoice"
    )
  }
}
