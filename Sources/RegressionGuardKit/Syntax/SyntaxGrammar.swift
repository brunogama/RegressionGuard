import Foundation

/// The swift-syntax grammar a run's trees were parsed with.
///
/// Recorded because an under-selected parser degrades silently: swift-syntax cannot represent
/// syntax newer than itself, so a rule written to catch a construct simply stops seeing it and
/// the change passes. A finding has to be traceable to the grammar that produced it, and a run
/// that read a guarded repository with an older grammar than it writes has to be auditable after
/// the fact.
///
/// Releases are aligned with language releases, so the major version is an alignment series
/// rather than a semantic major: 509 parses Swift 5.9 and 603 parses Swift 6.3. Each series is a
/// new major, which is why `from:` cannot float across them and the pin is a maintained decision.
public struct SyntaxGrammar: Codable, Equatable, Hashable, Sendable {
  /// The alignment series the guard is written against, and the one its manifest pins.
  ///
  /// The single place the decision lives, so bumping it is one edit rather than a search. Raise
  /// it when a new stable series ships and the package's range moves with it; a patch release
  /// inside a series cannot add syntax, so only the series matters here.
  public static let pinnedAlignmentSeries = 603

  /// The alignment series, for example `603`.
  ///
  /// The grammar's identity, and the only part a parsing target can always know about itself: a
  /// patch release within a series cannot add syntax, a series bump can.
  public let alignmentSeries: Int
  /// The resolved package version, for example `603.0.2`, when the run can tell.
  ///
  /// Optional because the series is established by compiling against a marker module, which
  /// names the series and nothing finer. A literal patch version would only drift from whatever
  /// actually resolved.
  public let version: String?

  /// A grammar known only by its series, which is what a marker module can establish.
  public init(alignmentSeries: Int) {
    self.init(alignmentSeries: alignmentSeries, version: nil)
  }

  /// Builds a grammar from a resolved swift-syntax version such as `603.0.2`.
  ///
  /// Fails when `version` does not lead with an alignment series, which is how a branch or
  /// revision pin arrives. Those cannot name a grammar, and saying so is better than inventing a
  /// series for them.
  ///
  /// - Parameter version: a resolved swift-syntax version such as `603.0.2`.
  public init?(version: String) {
    guard
      let series = version.split(separator: ".").first.flatMap({ Int($0) }),
      series > 0
    else { return nil }
    self.init(alignmentSeries: series, version: version)
  }

  /// Private so a series and a version can never disagree: every public path derives one from
  /// the other, and a report claiming `603.0.2` at series 509 would defeat the audit trail this
  /// type exists to provide.
  private init(alignmentSeries: Int, version: String?) {
    self.alignmentSeries = alignmentSeries
    self.version = version
  }

  /// The Swift release this series parses, for a human reading a report.
  public var swiftRelease: String {
    "\(alignmentSeries / 100).\(alignmentSeries % 100)"
  }

  /// `true` when this grammar is older than the series the guard pins.
  ///
  /// The only detectable form of the hazard that has no runtime signal. Syntax newer than the
  /// parser usually lands in an unexpected node and can be caught per file, but syntax that fits
  /// an existing open-ended production - a new attribute, say - parses into a well-formed node
  /// and is simply wrong. Nothing in the tree reveals that. Comparing the series the run
  /// actually got against the series the rules were written for is what remains.
  public var isUnderSelected: Bool {
    alignmentSeries < Self.pinnedAlignmentSeries
  }
}
