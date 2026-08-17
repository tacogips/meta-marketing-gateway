import Foundation
import MetaGraphPrimitives

/// Writer CLI deliberately exposes planning only until a separately managed
/// broker, principal verifier, asset verifier, and reconciler are composed.
/// This is production-safe: no local command can fall back to direct apply.
public enum WriterCLI {
  public static let version = "0.1.0"

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
      print(WriterCapabilityCatalog.json)
      return 0
    }
    guard arguments.count >= 2, arguments[0] == "graph", arguments[1] == "post"
    else { return fail("unknown writer command", 2) }
    let method = GraphMethod.post
    do {
      let options = try WriterOptions(Array(arguments.dropFirst(2)))
      let source = try WriterRequestSource.load(
        URL(fileURLWithPath: try options.required("--request-file")))
      let request = try source.request(
        method: method, version: GraphAPIVersion(try options.required("--api-version")))
      if options.value("--apply") == "true" {
        let confirmedAccount = try options.required("--confirm-account")
        guard source.adAccount == confirmedAccount,
          confirmedAccount.wholeMatch(of: /act_[0-9]+/) != nil,
          source.isBound(to: confirmedAccount), options.value("--plan-out") == nil
        else { throw GraphValidationError.policyDenied }
        let response = try await URLSessionGraphTransport().send(
          request, credential: KinkoEnvironmentCredentials().resolve())
        guard (200...299).contains(response.status) else {
          return fail(providerError(response.data, fallback: "provider rejected the write"), 4)
        }
        let provider = try JSONSerialization.jsonObject(with: response.data)
        let output = try JSONSerialization.data(
          withJSONObject: [
            "ok": true, "operation": "graph.post", "status": response.status,
            "provider": provider,
          ], options: [.sortedKeys])
        print(String(decoding: output, as: UTF8.self))
        return 0
      }
      guard let output = options.value("--plan-out"), options.value("--apply") == nil,
        options.value("--confirm-account") == nil
      else { throw GraphValidationError.policyDenied }
      let writer = MetaGraphWriter(transport: DenyingMutationTransport())
      let plan = try writer.offlinePlan(
        method: method, version: request.version, path: request.path, query: request.query,
        body: request.body, bodyMediaType: request.bodyMediaType, operationID: request.operationID)
      try SecureFile.writeNew(JSONEncoder().encode(plan), to: URL(fileURLWithPath: output))
      print(
        "{\"ok\":true,\"artifactKind\":\"offlinePlan\",\"operation\":\"graph.plan\",\"digest\":\"\(plan.planDigest)\",\"transportEligibility\":false}"
      )
      return 0
    } catch let error as GraphValidationError {
      return fail(error.localizedDescription, error == .policyDenied ? 6 : 2)
    } catch { return fail(GraphErrorSanitizer.sanitize(error), 70) }
  }

  private static func fail(_ message: String, _ code: Int32) -> Int32 {
    FileHandle.standardError.write(Data("{\"ok\":false,\"error\":\"\(message)\"}\n".utf8))
    return code
  }

  private static func providerError(_ data: Data, fallback: String) -> String {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = root["error"] as? [String: Any]
    else { return fallback }
    let code = error["code"].map { String(describing: $0) } ?? "unknown"
    let subcode = error["error_subcode"].map { "/\(String(describing: $0))" } ?? ""
    let details = [
      error["message"] as? String, error["error_user_title"] as? String,
      error["error_user_msg"] as? String,
    ].compactMap { $0 }.joined(separator: ": ")
    let message = (details.isEmpty ? fallback : details)
      .replacingOccurrences(of: "\n", with: " ").prefix(512)
    return "provider error \(code)\(subcode): \(message)"
  }

  private static let help = """
    meta-marketing-gateway-writer
    catalog list
    graph post --api-version vNN.N --request-file request.json --plan-out plan.json
    graph post --api-version vNN.N --request-file request.json --apply true --confirm-account act_N
    A live request file must bind `adAccount` and is restricted to POST. Physical deletion is unavailable from Writer.
    Credentials are accepted only through kinko exec --env META_ACCESS_TOKEN -- command.
    """
}

private struct DenyingMutationTransport: GraphTransport {
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    throw GraphValidationError.policyDenied
  }
}

private struct WriterOptions {
  private let storage: [String: [String]]
  init(_ tokens: [String]) throws {
    var result: [String: [String]] = [:]
    let prohibited: Set<String> = [
      "--access-token", "--authorization", "--header", "--env", "--url", "--proxy",
    ]
    var index = 0
    while index < tokens.count {
      guard tokens[index].hasPrefix("--"), !prohibited.contains(tokens[index]),
        index + 1 < tokens.count,
        !tokens[index + 1].hasPrefix("--")
      else { throw GraphValidationError.invalidRequest }
      result[tokens[index], default: []].append(tokens[index + 1])
      index += 2
    }
    guard
      Set(result.keys).isSubset(of: [
        "--api-version", "--request-file", "--plan-out", "--apply", "--confirm-account",
        "--confirm",
        "--acknowledge-high-impact", "--writer-config",
      ])
    else { throw GraphValidationError.invalidRequest }
    storage = result
  }
  func required(_ key: String) throws -> String {
    guard let values = storage[key], values.count == 1, let value = values.first else {
      throw GraphValidationError.invalidRequest
    }
    return value
  }
  func value(_ key: String) -> String? { storage[key]?.count == 1 ? storage[key]?.first : nil }
}

private struct WriterRequestSource: Decodable {
  let path: String
  let adAccount: String?
  let operationID: String?
  let query: [String: String]?
  let body: String?
  let bodyMediaType: GraphBodyMediaType?
  func request(method: GraphMethod, version: GraphAPIVersion) throws -> GraphRequest {
    try GraphRequest(
      method: method, version: version, path: GraphPath(relative: path),
      query: GraphQuery((query ?? [:]).sorted { $0.key < $1.key }),
      body: body.map { Data($0.utf8) },
      bodyMediaType: bodyMediaType, operationID: operationID)
  }
  static func load(_ url: URL) throws -> Self { try SecureFile.read(Self.self, from: url) }

  func isBound(to account: String) -> Bool {
    path == account || path.hasPrefix("\(account)/")
      || path.wholeMatch(of: /[0-9]+/) != nil
  }
}
