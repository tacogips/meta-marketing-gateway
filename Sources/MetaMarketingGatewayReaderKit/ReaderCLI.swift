import Foundation
import MetaGraphPrimitives

public enum ReaderCLI {
  public static let version = "0.1.0"

  public static func run(arguments: [String]) async -> Int32 {
    if arguments.contains("--help") || arguments.isEmpty {
      print(readerHelp)
      return 0
    }
    if arguments == ["--version"] {
      print(version)
      return 0
    }
    if arguments == ["catalog", "list"] {
      print(ReaderCapabilityCatalog.json)
      return 0
    }
    if arguments.first == "ads" {
      return await typedReader(arguments: Array(arguments.dropFirst()))
    }
    guard arguments.first == "graph", arguments.dropFirst().first == "get" else {
      return fail("unknown reader command", 2)
    }
    do {
      let options = try Options(Array(arguments.dropFirst(2)))
      let version = try GraphAPIVersion(options.required("--api-version"))
      let path = try GraphPath(relative: options.required("--path"))
      let query = try GraphQuery(options.values("--query").map(splitQuery))
      let reader = MetaGraphReader(transport: ReaderURLSessionGraphTransport())
      let response = try await reader.get(path: path, version: version, query: query)
      guard (200...299).contains(response.status) else {
        return fail(providerError(response.data, fallback: "provider rejected the request"), 4)
      }
      let provider = try JSONSerialization.jsonObject(with: response.data)
      let output = try JSONSerialization.data(
        withJSONObject: [
          "ok": true, "operation": "graph.get", "apiVersion": version.description,
          "status": response.status, "provider": provider,
        ], options: [.sortedKeys])
      print(String(decoding: output, as: UTF8.self))
      return 0
    } catch let error as GraphValidationError {
      return fail(error.localizedDescription, error == .missingCredential ? 3 : 2)
    } catch {
      return fail(GraphErrorSanitizer.sanitize(error), 5)
    }
  }

  private static func typedReader(arguments: [String]) async -> Int32 {
    guard arguments.count >= 2, arguments[0] == "list" || arguments[0] == "insights" else {
      return fail("unknown typed reader command", 2)
    }
    do {
      let command = arguments[0]
      let subject = arguments[1]
      let options = try Options(Array(arguments.dropFirst(2)))
      let listCapability = command == "list" ? try listDescriptor(subject) : nil
      var allowed: Set<String> = [
        "--api-version", "--fields", "--limit", "--after", "--filter-file",
      ]
      if command == "insights" {
        allowed.insert("--path")
      } else if listCapability?.requiresAccount == true {
        allowed.insert("--account")
      }
      try options.validate(allowed: allowed)
      let version = try GraphAPIVersion(options.required("--api-version"))
      let limit = try options.optional("--limit").map { value -> Int in
        guard value.wholeMatch(of: /[1-9][0-9]{0,5}/) != nil, let parsed = Int(value) else {
          throw GraphValidationError.invalidPagination
        }
        return parsed
      }
      let page = try PageRequest(
        limit: limit,
        direction: try options.optional("--after").map { .after(try PageCursor($0)) })
      let filters: [MetaAdsFilter] =
        try options.optional("--filter-file").map {
          try MetaAdsFilterEncoding.loadFile(URL(fileURLWithPath: $0))
        } ?? []
      let graph = MetaGraphReader(transport: ReaderURLSessionGraphTransport())
      let ads = try MetaAdsReader(reader: graph, version: version)
      if command == "insights" {
        guard let insightSubject = MetaAdsInsightSubject(rawValue: subject) else {
          throw GraphValidationError.invalidRequest
        }
        let fields = try fields(from: options.required("--fields"), domain: .insight)
        let path = try GraphPath(relative: options.required("--path"))
        try insightSubject.validate(path: path)
        let result = try await ads.insights(
          path: path, options: MetaAdsListOptions(fields: fields, filters: filters, page: page))
        print(
          "{\"ok\":true,\"operation\":\"meta.ads.insights.read\",\"count\":\(result.data.count)}")
        return 0
      }
      guard let descriptor = listCapability else { throw GraphValidationError.invalidRequest }
      let domain = descriptor.domain
      let operation = descriptor.operationID
      let selection = try fields(from: options.required("--fields"), domain: domain)
      let request = try MetaAdsListOptions(fields: selection, filters: filters, page: page)
      let account: AdAccountID?
      if subject == "adaccounts" {
        account = nil
      } else {
        account = try AdAccountID(options.required("--account"))
      }
      let count: Int
      switch subject {
      case "adaccounts": count = try await ads.adAccounts(request).data.count
      case "campaigns":
        count = try await ads.campaigns(try requiredAccount(account), options: request).data.count
      case "adsets":
        count = try await ads.adSets(try requiredAccount(account), options: request).data.count
      case "ads":
        count = try await ads.ads(try requiredAccount(account), options: request).data.count
      case "adcreatives":
        count = try await ads.adCreatives(try requiredAccount(account), options: request).data.count
      default: throw GraphValidationError.invalidRequest
      }
      print("{\"ok\":true,\"operation\":\"\(operation)\",\"count\":\(count)}")
      return 0
    } catch let error as GraphValidationError {
      return fail(error.localizedDescription, error == .missingCredential ? 3 : 2)
    } catch { return fail(GraphErrorSanitizer.sanitize(error), 5) }
  }

  private static func fields(from value: String, domain: MetaAdsDomain) throws -> FieldSelection {
    let entries = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    return try FieldSelection(entries, domain: domain)
  }

  private static func listDescriptor(_ subject: String) throws
    -> MetaAdsCapabilityCatalog.Descriptor
  {
    guard let descriptor = MetaAdsCapabilityCatalog.listDescriptor(for: subject) else {
      throw GraphValidationError.invalidRequest
    }
    return descriptor
  }

  private static func requiredAccount(_ account: AdAccountID?) throws -> AdAccountID {
    guard let account else { throw GraphValidationError.invalidRequest }
    return account
  }

  private static func splitQuery(_ item: String) -> (String, String) {
    let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    return (String(pair.first ?? ""), pair.count == 2 ? String(pair[1]) : "")
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
    let details = [error["message"] as? String, error["error_user_msg"] as? String]
      .compactMap { $0 }.joined(separator: ": ")
    let message = (details.isEmpty ? fallback : details)
      .replacingOccurrences(of: "\n", with: " ").prefix(512)
    return "provider error \(code)\(subcode): \(message)"
  }
  private static let readerHelp = """
    meta-marketing-gateway-reader
    graph get --api-version vNN.N --path relative/node [--query key=value]
    catalog list
    ads list adaccounts --api-version vNN.N --fields field[,field] [--filter-file filters.json]
    ads list campaigns|adsets|ads|adcreatives --api-version vNN.N --account act_N --fields field[,field] [--filter-file filters.json]
    ads insights account|campaign|adset|ad --api-version vNN.N --path relative/node --fields field[,field] [--filter-file filters.json]
    Catalog discovery is local; credentials are accepted only through kinko exec --env META_ACCESS_TOKEN -- command.
    """
}

private struct Options {
  private let storage: [String: [String]]
  init(_ tokens: [String]) throws {
    var parsed: [String: [String]] = [:]
    var index = 0
    let prohibited = Set([
      "--access-token", "--app-secret", "--authorization", "--header", "--url", "--origin",
      "--method", "--cookie", "--proxy", "--env",
    ])
    while index < tokens.count {
      let key = tokens[index]
      guard key.hasPrefix("--"), !prohibited.contains(key), index + 1 < tokens.count,
        !tokens[index + 1].hasPrefix("--")
      else { throw GraphValidationError.invalidRequest }
      parsed[key, default: []].append(tokens[index + 1])
      index += 2
    }
    self.storage = parsed
  }
  func required(_ key: String) throws -> String {
    guard let values = storage[key], values.count == 1, let value = values.first else {
      throw GraphValidationError.invalidRequest
    }
    return value
  }
  func optional(_ key: String) throws -> String? {
    guard let values = storage[key] else { return nil }
    guard values.count == 1 else { throw GraphValidationError.invalidRequest }
    return values[0]
  }
  /// Legacy writer parsing still treats duplicate mutually exclusive flags as
  /// invalid at its own decision points. Typed read commands use `optional`.
  func value(_ key: String) -> String? { storage[key]?.count == 1 ? storage[key]?.first : nil }
  func values(_ key: String) -> [String] { storage[key] ?? [] }
  func validate(allowed: Set<String>) throws {
    guard storage.keys.allSatisfy(allowed.contains) else {
      throw GraphValidationError.invalidRequest
    }
  }
}
