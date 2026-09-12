import Foundation
import Testing
@testable import GoldenMaster

/// `.serialized` because these tests switch recording on and off through the process environment.
/// Swift Testing runs a suite's tests in parallel by default, which would let one test's
/// `GM_RECORD` leak into another's verification and silently turn it into a recording - XCTest
/// ran them one at a time, and that ordering is part of what they assert.
@Suite("Characterization tests", .serialized)
struct CharacterizationTests {

  init() {
    unsetenv("GM_RECORD")
  }

  @Test("records, then verifies a matching snapshot")
  func recordsThenVerifiesAMatchingSnapshot() throws {
    setenv("GM_RECORD", "1", 1)
    try Characterization.verify("hello world", identifier: "record")
    unsetenv("GM_RECORD")

    try Characterization.verify("hello world", identifier: "record")
  }

  @Test("a mismatch throws")
  func mismatchThrows() throws {
    setenv("GM_RECORD", "1", 1)
    try Characterization.verify("version one", identifier: "mismatch")
    unsetenv("GM_RECORD")

    #expect(throws: CharacterizationMismatch.self) {
      try Characterization.verify("version two", identifier: "mismatch")
    }
  }

  @Test("a missing snapshot throws by default")
  func missingSnapshotThrowsByDefault() throws {
    // Use a unique identifier so a previous run's recording can't mask this failing.
    let identifier = "missing-\(UUID().uuidString)"
    #expect(throws: CharacterizationMissing.self) {
      try Characterization.verify("anything", identifier: identifier)
    }
  }

  struct SampleInvoice: Encodable {
    let id: Int
    let total: Double
  }

  @Test("an encodable snapshot records stable JSON")
  func encodableSnapshotRecordsStableJSON() throws {
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
