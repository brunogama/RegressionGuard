import Foundation
import Testing

@testable import RegressionGuardKit

@Suite("Syntax grammar tests")
struct SyntaxGrammarTests {
  @Test("a grammar derives its alignment series from the version it was built from")
  func seriesFromVersion() throws {
    let grammar = try #require(SyntaxGrammar(version: "603.0.2"))
    #expect(grammar.version == "603.0.2")
    #expect(grammar.alignmentSeries == 603)
  }

  @Test("a grammar known only by its series names no version, rather than inventing one")
  func seriesOnlyGrammar() {
    let grammar = SyntaxGrammar(alignmentSeries: 603)
    #expect(grammar.version == nil)
    #expect(grammar.alignmentSeries == 603)
  }

  @Test("a series older than the pin is under-selected, and newer syntax may be invisible")
  func detectsUnderSelection() {
    #expect(SyntaxGrammar(alignmentSeries: 600).isUnderSelected)
    #expect(SyntaxGrammar(alignmentSeries: 602).isUnderSelected)
    #expect(!SyntaxGrammar(alignmentSeries: SyntaxGrammar.pinnedAlignmentSeries).isUnderSelected)
    #expect(!SyntaxGrammar(alignmentSeries: 604).isUnderSelected)
  }

  @Test("a version with no leading series is not a grammar")
  func rejectsUnparseableVersion() {
    #expect(SyntaxGrammar(version: "main") == nil)
    #expect(SyntaxGrammar(version: "") == nil)
  }

  @Test("an alignment series names the Swift release it parses")
  func swiftReleaseMapping() {
    #expect(SyntaxGrammar(alignmentSeries: 603).swiftRelease == "6.3")
    #expect(SyntaxGrammar(alignmentSeries: 600).swiftRelease == "6.0")
    #expect(SyntaxGrammar(alignmentSeries: 510).swiftRelease == "5.10")
    #expect(SyntaxGrammar(alignmentSeries: 509).swiftRelease == "5.9")
  }

  @Test("a grammar survives a round trip through the report encoding")
  func codableRoundTrip() throws {
    let grammar = try #require(SyntaxGrammar(version: "603.0.2"))
    let data = try JSONEncoder().encode(grammar)
    #expect(try JSONDecoder().decode(SyntaxGrammar.self, from: data) == grammar)
  }
}
