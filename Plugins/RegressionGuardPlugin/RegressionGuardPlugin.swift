import Foundation
import PackagePlugin

/// `swift package regression-guard [--base <ref>] [--head <ref>]`
///
/// Runs the same checks as CI, locally, against your working tree — so an agent (or you) finds
/// out about a disabled test before it's even committed, not after a PR is opened.
@main
struct RegressionGuardPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) throws {
    let tool = try context.tool(named: "regression-guard")

    var passthroughArguments = ["check"]
    if arguments.isEmpty {
      passthroughArguments += ["--base", "HEAD"]
    } else {
      passthroughArguments += arguments
    }
    passthroughArguments += ["--path", context.package.directory.string]

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool.path.string)
    process.arguments = passthroughArguments
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      Diagnostics.error("regression-guard found violations — see output above.")
    }
  }
}
