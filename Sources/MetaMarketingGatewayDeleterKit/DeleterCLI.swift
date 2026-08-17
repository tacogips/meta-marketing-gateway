import Foundation
import MetaGraphPrimitives

public enum DeleterCLI {
  public static let version = "0.2.0"

  public static func run(arguments: [String]) async -> Int32 {
    if arguments.isEmpty || arguments.contains("--help") {
      print(help)
      return 0
    }
    if arguments == ["--version"] {
      print(version)
      return 0
    }
    if arguments == ["catalog", "list"] {
      print(DeleterCapabilityCatalog.json)
      return 0
    }
    guard arguments.count >= 2, arguments[0] == "graph", arguments[1] == "delete" else {
      return fail("unknown deleter command", 2)
    }
    do {
      let options = try DeleterOptions(Array(arguments.dropFirst(2)))
      let version = try GraphAPIVersion(options.required("--api-version"))
      let path = try GraphPath(relative: options.required("--path"))
      let confirmation = try options.required("--confirm-path")
      let query = try GraphQuery(options.values("--query").map(splitQuery))
      let response = try await MetaGraphDeleter().delete(
        version: version, path: path, query: query, confirmedPath: confirmation)
      guard (200...299).contains(response.status) else {
        return fail("provider rejected the delete", 4)
      }
      print("{\"ok\":true,\"operation\":\"graph.delete\",\"status\":\(response.status)}")
      return 0
    } catch let error as GraphValidationError {
      return fail(error.localizedDescription, error == .missingCredential ? 3 : 2)
    } catch { return fail(GraphErrorSanitizer.sanitize(error), 5) }
  }

  private static func splitQuery(_ item: String) -> (String, String) {
    let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    return (String(pair.first ?? ""), pair.count == 2 ? String(pair[1]) : "")
  }
  private static func fail(_ message: String, _ code: Int32) -> Int32 {
    FileHandle.standardError.write(Data("{\"ok\":false,\"error\":\"\(message)\"}\n".utf8))
    return code
  }
  private static let help = """
    meta-marketing-gateway-deleter
    catalog list
    graph delete --api-version vNN.N --path relative/node --confirm-path relative/node [--query key=value]
    The exact canonical path must be repeated. Credentials are accepted only through kinko exec --env META_ACCESS_TOKEN -- command.
    """
}

private struct DeleterOptions {
  private let storage: [String: [String]]
  init(_ tokens: [String]) throws {
    var parsed: [String: [String]] = [:]
    let allowed = Set(["--api-version", "--path", "--confirm-path", "--query"])
    var index = 0
    while index < tokens.count {
      guard index + 1 < tokens.count, allowed.contains(tokens[index]),
        !tokens[index + 1].hasPrefix("--")
      else { throw GraphValidationError.invalidRequest }
      parsed[tokens[index], default: []].append(tokens[index + 1])
      index += 2
    }
    storage = parsed
  }
  func required(_ key: String) throws -> String {
    guard let values = storage[key], values.count == 1, let value = values.first else {
      throw GraphValidationError.invalidRequest
    }
    return value
  }
  func values(_ key: String) -> [String] { storage[key] ?? [] }
}
