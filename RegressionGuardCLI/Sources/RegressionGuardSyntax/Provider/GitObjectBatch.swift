import Foundation

/// Reads many `<ref>:<path>` objects out of a repository in a single `git cat-file --batch`.
///
/// Synchronous on purpose. `SyntacticEvidenceProvider` is a synchronous interface because
/// everything a run needs is resolved in one call, and wrapping one spawn in an actor would buy
/// nothing but a hop. The whole point of the batch is that there is exactly one of them per run.
struct GitObjectBatch {
  enum Failure: Error, CustomStringConvertible {
    /// git answered, and the object is not in the repository at that ref.
    case missing
    /// git itself failed - an unreachable ref, a directory that is not a repository.
    case gitFailed(String)

    var description: String {
      switch self {
      case .missing: return "no such object"
      case .gitFailed(let message): return message
      }
    }
  }

  let repositoryDirectory: URL

  /// - Returns: one result per requested name, keyed by the name as it was asked for.
  func read(_ names: [String]) -> [String: Result<Data, Failure>] {
    guard !names.isEmpty else { return [:] }

    let process = Process()
    process.currentDirectoryURL = repositoryDirectory
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "cat-file", "--batch"]

    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors

    do {
      try process.run()
    } catch {
      return failAll(names, with: .gitFailed("could not spawn git: \(error)"))
    }

    // Written from another thread while this one drains stdout. git answers as it reads, so
    // writing the whole request first and reading afterwards deadlocks once either pipe's buffer
    // fills - which a real diff reaches long before the file counts this exists to serve.
    let request = Data((names.joined(separator: "\n") + "\n").utf8)
    DispatchQueue.global(qos: .userInitiated).async {
      input.fileHandleForWriting.write(request)
      try? input.fileHandleForWriting.close()
    }

    let answered = output.fileHandleForReading.readDataToEndOfFile()
    let failure = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let message = String(data: failure, encoding: .utf8) ?? "git cat-file failed"
      return failAll(names, with: .gitFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return parse(answered, for: names)
  }

  /// Pairs the answers with the names by position, which is the only link git gives back.
  ///
  /// A found object's header names its oid rather than the object asked for, so nothing in the
  /// output identifies the request except its order. A malformed or truncated answer stops the
  /// walk, and every name left unpaired is a failure rather than an absence.
  private func parse(_ data: Data, for names: [String]) -> [String: Result<Data, Failure>] {
    var results: [String: Result<Data, Failure>] = [:]
    var cursor = data.startIndex

    for name in names {
      guard let lineEnd = data[cursor...].firstIndex(of: UInt8(ascii: "\n")) else { break }
      let header = String(decoding: data[cursor..<lineEnd], as: UTF8.self)
      cursor = data.index(after: lineEnd)

      let fields = header.split(separator: " ")
      guard fields.count == 3, let size = Int(fields[2]) else {
        // `<name> missing`, and anything else malformed enough that the rest cannot be trusted.
        results[name] = .failure(header.hasSuffix("missing") ? .missing : .gitFailed(header))
        if !header.hasSuffix("missing") { break }
        continue
      }

      guard let contentEnd = data.index(cursor, offsetBy: size, limitedBy: data.endIndex) else {
        results[name] = .failure(.gitFailed("truncated answer for \(name)"))
        break
      }
      results[name] = .success(data[cursor..<contentEnd])
      // git writes a newline after the content, which is not part of the object.
      cursor = data.index(contentEnd, offsetBy: 1, limitedBy: data.endIndex) ?? data.endIndex
    }

    for name in names where results[name] == nil {
      results[name] = .failure(.gitFailed("git answered nothing for \(name)"))
    }
    return results
  }

  private func failAll(_ names: [String], with failure: Failure) -> [String: Result<Data, Failure>]
  {
    Dictionary(uniqueKeysWithValues: names.map { ($0, .failure(failure)) })
  }
}
