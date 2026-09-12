import RegressionGuardKit
import Testing

@testable import RegressionGuardSyntax

@Suite("Compiled syntax grammar tests")
struct CompiledSyntaxGrammarTests {
  @Test("reports the series it was compiled against, observed from the marker module")
  func reportsCompiledSeries() throws {
    // A build that cannot name its grammar emits reports indistinguishable from a run that had no
    // parser at all, which is the silent degradation this package exists to catch.
    let grammar = try #require(CompiledSyntaxGrammar.current)
    #expect(grammar.alignmentSeries == SyntaxGrammar.pinnedAlignmentSeries)
  }

  @Test("a build on the pinned series is not under-selected")
  func pinnedSeriesIsNotUnderSelected() throws {
    let grammar = try #require(CompiledSyntaxGrammar.current)
    #expect(!grammar.isUnderSelected)
  }

  @Test("names no patch version, because a marker module establishes only the series")
  func namesNoPatchVersion() throws {
    let grammar = try #require(CompiledSyntaxGrammar.current)
    #expect(grammar.version == nil)
  }
}
