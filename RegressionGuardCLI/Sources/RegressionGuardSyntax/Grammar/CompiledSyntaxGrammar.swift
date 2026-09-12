import RegressionGuardKit

/// The swift-syntax grammar this target was actually compiled against.
///
/// Observed rather than asserted. swift-syntax ships a `SwiftSyntax<series>` marker module for
/// every alignment series it belongs to, so `canImport` answers which grammar the build resolved.
/// A literal would drift from whatever the resolver actually picked, and a report naming a grammar
/// the run did not use is worse than one naming none.
///
/// This is also the reason the offline route vendors swift-syntax as source instead of borrowing
/// the toolchain's own modules at `usr/lib/swift/host`: those parse correctly but ship no marker
/// module, so a build against them could not answer this question at all.
public enum CompiledSyntaxGrammar {
  /// The grammar this build parses with, or `nil` when no known marker module is visible.
  ///
  /// `nil` means the build resolved a series this target has no marker for - a newer one, or a
  /// prerelease. Saying nothing beats guessing, because `SyntaxGrammar.isUnderSelected` compares
  /// against the pin and a wrong series would answer that comparison wrongly.
  public static let current: SyntaxGrammar? = series.map(SyntaxGrammar.init(alignmentSeries:))

  private static var series: Int? {
    // Ordered newest first: a checkout on 603 also carries the 602 and earlier markers, since a
    // release belongs to every series up to its own.
    #if canImport(SwiftSyntax603)
      return 603
    #elseif canImport(SwiftSyntax602)
      return 602
    #elseif canImport(SwiftSyntax601)
      return 601
    #elseif canImport(SwiftSyntax600)
      return 600
    #else
      return nil
    #endif
  }
}
