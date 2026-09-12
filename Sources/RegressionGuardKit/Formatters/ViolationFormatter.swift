import Foundation

public protocol ViolationFormatter {
  func format(_ violations: [Violation]) -> String
}

public struct TextFormatter: ViolationFormatter {
  public init() {}

  public func format(_ violations: [Violation]) -> String {
    guard !violations.isEmpty else {
      return "regression-guard: no violations found."
    }

    var lines: [String] = []
    for violation in violations.sorted(by: { $0.severity > $1.severity }) {
      append(violation, to: &lines)
    }

    let errorCount = violations.filter { $0.severity == .error }.count
    let warningCount = violations.filter { $0.severity == .warning }.count
    lines.append("")
    lines.append(summary(errors: errorCount, warnings: warningCount, total: violations.count))
    return lines.joined(separator: "\n")
  }

  private func append(_ violation: Violation, to lines: inout [String]) {
    let location = violation.line.map { "\(violation.file):\($0)" } ?? violation.file
    lines.append("[\(violation.severity.rawValue.uppercased())] \(violation.ruleID) - \(location)")
    lines.append("  \(violation.message)")
    appendDetail(violation.detail, to: &lines)
  }

  private func appendDetail(_ detail: String?, to lines: inout [String]) {
    guard let detail, !detail.isEmpty else { return }
    for detailLine in detail.split(separator: "\n") {
      lines.append("    | \(detailLine)")
    }
  }

  private func summary(errors: Int, warnings: Int, total: Int) -> String {
    "regression-guard: \(errors) error(s), \(warnings) warning(s), \(total) total."
  }
}

public struct JSONFormatter: ViolationFormatter {
  public init() {}

  public func format(_ violations: [Violation]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(violations),
      let string = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return string
  }
}

/// Emits GitHub Actions workflow-command annotations so violations surface inline on the PR diff.
/// https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
public struct GitHubAnnotationFormatter: ViolationFormatter {
  public init() {}

  public func format(_ violations: [Violation]) -> String {
    violations.map { violation in
      let command = command(for: violation.severity)
      var params = "file=\(violation.file)"
      if let line = violation.line { params += ",line=\(line)" }
      params += ",title=\(violation.ruleID)"
      let message = violation.message.replacingOccurrences(of: "\n", with: "%0A")
      return "::\(command) \(params)::\(message)"
    }.joined(separator: "\n")
  }

  private func command(for severity: Severity) -> String {
    switch severity {
    case .error: return "error"
    case .warning: return "warning"
    case .info: return "notice"
    }
  }
}
