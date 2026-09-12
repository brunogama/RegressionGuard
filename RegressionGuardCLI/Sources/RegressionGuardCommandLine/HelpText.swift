import Commander

/// Renders `--help` from a command descriptor.
///
/// Commander ships no help rendering at all, and a CLI that cannot describe itself is a worse tool
/// than one that can. The descriptor already carries every name, abstract, and help string the
/// signature declared, so this reads from the same source the parser does - help and behaviour
/// cannot drift apart.
public enum HelpText {
  /// - Parameters:
  ///   - descriptor: the resolved command.
  ///   - path: the tokens that selected it, used to echo the invocation back.
  public static func render(_ descriptor: CommandDescriptor, invokedAs path: [String]) -> String {
    var sections = ["OVERVIEW: \(descriptor.abstract)"]
    if let discussion = descriptor.discussion, !discussion.isEmpty {
      sections.append(discussion)
    }
    sections.append("USAGE: \(usage(descriptor, path: path))")
    if let options = optionSection(descriptor) {
      sections.append(options)
    }
    if let subcommands = subcommandSection(descriptor) {
      sections.append(subcommands)
    }
    return sections.joined(separator: "\n\n")
  }

  private static func usage(_ descriptor: CommandDescriptor, path: [String]) -> String {
    var parts = path
    let signature = descriptor.signature.flattened()
    if !descriptor.subcommands.isEmpty {
      parts.append("<subcommand>")
    }
    for option in signature.options {
      parts.append("[--\(name(of: option)) <\(ParsedOptions.optionName(for: option.label))>]")
    }
    for flag in signature.flags {
      parts.append("[--\(ParsedOptions.optionName(for: flag.label))]")
    }
    return parts.joined(separator: " ")
  }

  private static func optionSection(_ descriptor: CommandDescriptor) -> String? {
    let signature = descriptor.signature.flattened()
    var rows: [(String, String)] = signature.options.map { option in
      ("--\(name(of: option)) <\(ParsedOptions.optionName(for: option.label))>", option.help ?? "")
    }
    rows += signature.flags.map { flag in
      ("--\(ParsedOptions.optionName(for: flag.label))", flag.help ?? "")
    }
    rows.append(("--help", "Show this help."))
    return section("OPTIONS", rows: rows)
  }

  private static func subcommandSection(_ descriptor: CommandDescriptor) -> String? {
    section(
      "SUBCOMMANDS",
      rows: descriptor.subcommands.map { child in
        let isDefault = child.name == descriptor.defaultSubcommandName
        return (child.name, child.abstract + (isDefault ? " (default)" : ""))
      }
    )
  }

  private static func section(_ title: String, rows: [(String, String)]) -> String? {
    guard !rows.isEmpty else { return nil }
    let width = rows.map(\.0.count).max() ?? 0
    let lines = rows.map { label, detail in
      let padding = String(repeating: " ", count: width - label.count)
      return detail.isEmpty ? "  \(label)" : "  \(label)\(padding)  \(detail)"
    }
    return ([title + ":"] + lines).joined(separator: "\n")
  }

  /// The long spelling, falling back to the label when a definition declares only a short name.
  private static func name(of option: OptionDefinition) -> String {
    for optionName in option.names {
      if case .long(let long) = optionName { return long }
    }
    return ParsedOptions.optionName(for: option.label)
  }
}
