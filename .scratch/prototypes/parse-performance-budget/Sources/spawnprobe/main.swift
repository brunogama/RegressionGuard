import Foundation
import ParseBenchCore

// Asks where a subprocess's cost actually goes.
//
// The benchmark measures a far higher per-spawn cost than a shell does, and the budget has to say
// whether that is git's work or the way Foundation starts it. Four shapes of the same 30 reads
// answer it: a no-op binary isolates process creation, `env git` prices the indirection
// `GitRepository` uses today, and one `cat-file --batch` is the alternative being argued for.

let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// 30 tracked Swift files, the same sample size the capability research used.
let paths = String(decoding: GitCommand.run(["ls-files", "*.swift"], in: repo), as: UTF8.self)
  .split(separator: "\n")
  .prefix(30)
  .map(String.init)

guard !paths.isEmpty else {
  FileHandle.standardError.write(Data("no Swift files tracked in \(repo)\n".utf8))
  exit(1)
}

func report(_ label: String, over count: Int, _ body: () -> Void) {
  let ms = seconds(body) * 1000
  let padded = label.padding(toLength: 34, withPad: " ", startingAt: 0)
  print(padded + String(format: "%8.1f ms total %7.2f ms each", ms, ms / Double(count)))
  // Output is a file whenever this runs in the background, and a file is block-buffered.
  fflush(stdout)
}

print("repo \(repo), \(paths.count) files")

// The first spawn in a process pays for lazily initialised Foundation state.
for _ in 0..<3 { _ = GitCommand.run(["--version"], in: repo) }

report("git show", over: paths.count) {
  for path in paths { _ = GitCommand.run(["show", "HEAD:\(path)"], in: repo) }
}
report("git cat-file --batch (1 spawn)", over: 1) {
  let specs = paths.map { "HEAD:\($0)" }.joined(separator: "\n") + "\n"
  _ = GitCommand.run(["cat-file", "--batch"], in: repo, stdin: Data(specs.utf8))
}

// These two do not go through GitCommand, because neither is a git command: one runs no program
// worth naming and the other deliberately adds an exec in front of git.
report("true (no work at all)", over: paths.count) {
  for _ in paths { _ = spawn("/usr/bin/true", []) }
}
report("env git show", over: paths.count) {
  for path in paths { _ = spawn("/usr/bin/env", ["git", "show", "HEAD:\(path)"]) }
}

/// Runs `executable` and discards its output, for the two comparisons that are not git commands.
func spawn(_ executable: String, _ arguments: [String]) -> Int {
  let process = Process()
  process.currentDirectoryURL = URL(fileURLWithPath: repo)
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let output = Pipe()
  process.standardOutput = output
  process.standardError = Pipe()
  do {
    try process.run()
  } catch {
    fatalError("could not spawn \(executable): \(error)")
  }
  let count = output.fileHandleForReading.readDataToEndOfFile().count
  process.waitUntilExit()
  return count
}
