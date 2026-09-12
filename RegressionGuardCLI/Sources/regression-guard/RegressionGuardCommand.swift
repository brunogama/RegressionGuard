import Commander
import Foundation
import RegressionGuardCommandLine

/// The `regression-guard` executable.
///
/// Commander resolves a command and parses its arguments; running one, choosing a default
/// subcommand, and answering `--help` are this file's job, because the package does none of them.
@main
@MainActor
enum RegressionGuardCommand {
  static let commandName = "regression-guard"
  static let abstract = "Catches shortcuts around failing tests instead of fixing them."
  static let defaultSubcommand = "check"

  static func main() async {
    // `Program.resolve` expects a command name first and strips `argv[0]` only when it ends in
    // "peekaboo", so the executable name is dropped here rather than relied upon.
    let arguments = Array(CommandLine.arguments.dropFirst())
    await CommandLineDriver.run { try await dispatch(arguments) }
  }

  private static func dispatch(_ arguments: [String]) async throws {
    let descriptors = [
      descriptor(Check.self),
      descriptor(Coverage.self),
      descriptor(Init.self),
    ]

    // Answered before the default subcommand is filled in, so a bare `--help` describes the tool
    // rather than describing `check` as though the user had asked for it.
    if CommandLineDriver.wantsHelp(arguments) {
      CommandLineDriver.write(help(for: arguments.first, among: descriptors))
      return
    }

    // A bare `regression-guard --base X` has no subcommand token, which the router would read as
    // an unknown command. ArgumentParser's `defaultSubcommand` covered this, so it is restored
    // here: anything that does not name a known command is a `check` invocation.
    var routed = arguments
    if routed.first.map({ name in !descriptors.contains { $0.name == name } }) ?? true {
      routed.insert(defaultSubcommand, at: 0)
    }

    let invocation = try Program(descriptors: descriptors).resolve(argv: routed)
    let options = ParsedOptions(invocation.parsedValues)
    switch invocation.descriptor.name {
    case Check.commandDescription.commandName:
      try await Check(options: options).run()
    case Coverage.commandDescription.commandName:
      try Coverage(options: options).run()
    case Init.commandDescription.commandName:
      try Init(options: options).run()
    default:
      throw ValidationError("Unknown command '\(invocation.descriptor.name)'")
    }
  }

  /// Help for the named subcommand, or for the tool itself when the name is not one.
  private static func help(for name: String?, among descriptors: [CommandDescriptor]) -> String {
    if let name, let match = descriptors.first(where: { $0.name == name }) {
      return HelpText.render(match, invokedAs: [commandName, match.name])
    }
    let root = CommandDescriptor(
      name: commandName,
      abstract: abstract,
      discussion: nil,
      signature: CommandSignature(),
      subcommands: descriptors,
      defaultSubcommandName: defaultSubcommand
    )
    return HelpText.render(root, invokedAs: [commandName])
  }

  private static func descriptor(_ type: (some ParsableCommand).Type) -> CommandDescriptor {
    let description = type.commandDescription
    return CommandDescriptor(
      name: description.commandName ?? String(describing: type).lowercased(),
      abstract: description.abstract,
      discussion: description.discussion,
      signature: CommandSignature.describe(type.init())
    )
  }
}
