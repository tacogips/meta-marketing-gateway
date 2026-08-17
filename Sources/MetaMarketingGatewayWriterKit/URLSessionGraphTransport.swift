import Darwin
import Foundation
import MetaGraphPrimitives

public struct URLSessionGraphTransport: GraphTransport, GraphMultipartUploading {
  private static let maximumResponseBytes = 4_194_304
  private let configuration: URLSessionConfiguration

  public init() {
    configuration = Self.secureConfiguration()
  }

  /// Test-only configuration injection keeps URL construction, redirect denial,
  /// and credential handling in this transport while allowing deterministic
  /// `URLProtocol` contracts. Production callers use `init()`.
  init(configuration: URLSessionConfiguration) {
    self.configuration = configuration
  }

  public func send(_ request: GraphRequest, credential: GraphCredential) async throws
    -> GraphResponse
  {
    guard request.method == .post else { throw GraphValidationError.policyDenied }
    let url = try request.url()
    var outgoing = URLRequest(url: url)
    outgoing.httpMethod = request.method.rawValue
    outgoing.httpBody = request.body
    outgoing.timeoutInterval = 30
    if let bodyMediaType = request.bodyMediaType {
      outgoing.setValue(bodyMediaType.rawValue, forHTTPHeaderField: "Content-Type")
    }
    credential.applyAuthorization(to: &outgoing)
    let session = makeSession()
    let (bytes, response) = try await session.bytes(for: outgoing)
    guard let http = response as? HTTPURLResponse else { throw GraphValidationError.invalidRequest }
    let data = try await Self.collect(bytes)
    return try GraphResponse(status: http.statusCode, data: data)
  }

  func sendForTesting(_ request: GraphRequest, credential: GraphCredential) async throws
    -> GraphResponse
  {
    let url = try request.url()
    var outgoing = URLRequest(url: url)
    outgoing.httpMethod = request.method.rawValue
    outgoing.httpBody = request.body
    outgoing.timeoutInterval = 30
    if let bodyMediaType = request.bodyMediaType {
      outgoing.setValue(bodyMediaType.rawValue, forHTTPHeaderField: "Content-Type")
    }
    credential.applyAuthorization(to: &outgoing)
    let session = makeSession()
    let (bytes, response) = try await session.bytes(for: outgoing)
    guard let http = response as? HTTPURLResponse else { throw GraphValidationError.invalidRequest }
    return try GraphResponse(status: http.statusCode, data: try await Self.collect(bytes))
  }

  public func upload(
    path: GraphPath, version: GraphAPIVersion, boundary: String, body: GraphMultipartBodyStream,
    credential: GraphCredential
  ) async throws -> GraphResponse {
    throw GraphValidationError.policyDenied
  }

  func uploadForTesting(
    path: GraphPath, version: GraphAPIVersion, boundary: String, body: GraphMultipartBodyStream,
    credential: GraphCredential
  ) async throws -> GraphResponse {
    guard Self.isApprovedUploadPath(path.description) else {
      throw GraphValidationError.policyDenied
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
      "meta-marketing-upload-test-\(UUID().uuidString)")
    let descriptor = open(
      temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw GraphValidationError.invalidRequest }
    defer {
      close(descriptor)
      try? FileManager.default.removeItem(at: temporary)
    }
    while let chunk = try body.nextChunk() {
      var offset = 0
      while offset < chunk.count {
        let written = chunk.withUnsafeBytes {
          Darwin.write(descriptor, $0.baseAddress!.advanced(by: offset), chunk.count - offset)
        }
        guard written > 0 else { throw GraphValidationError.invalidRequest }
        offset += written
      }
    }
    guard fsync(descriptor) == 0 else { throw GraphValidationError.invalidRequest }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "graph.facebook.com"
    components.path = "/\(version.description)/\(path.description)"
    guard let url = components.url else { throw GraphValidationError.invalidRequest }
    var outgoing = URLRequest(url: url)
    outgoing.httpMethod = GraphMethod.post.rawValue
    outgoing.timeoutInterval = 30
    outgoing.httpBodyStream = InputStream(url: temporary)
    outgoing.setValue("\(try Self.fileSize(temporary))", forHTTPHeaderField: "Content-Length")
    outgoing.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    credential.applyAuthorization(to: &outgoing)
    let session = makeSession()
    let (bytes, response) = try await session.bytes(for: outgoing)
    guard let http = response as? HTTPURLResponse else { throw GraphValidationError.invalidRequest }
    return try GraphResponse(status: http.statusCode, data: try await Self.collect(bytes))
  }

  static func isApprovedUploadPath(_ path: String) -> Bool {
    path.wholeMatch(of: /act_[0-9]+\/adimages/) != nil
  }

  private static func fileSize(_ url: URL) throws -> Int {
    var information = stat()
    guard lstat(url.path, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG,
      information.st_size >= 0
    else { throw GraphValidationError.invalidRequest }
    return Int(information.st_size)
  }

  private static func secureConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
  }

  private func makeSession() -> URLSession {
    URLSession(
      configuration: configuration, delegate: RejectingRedirectDelegate(), delegateQueue: nil)
  }

  private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
      guard data.count < maximumResponseBytes else { throw GraphValidationError.invalidRequest }
      data.append(byte)
    }
    return data
  }
}

final class RejectingRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard request.url?.scheme == "https", request.url?.host == "graph.facebook.com" else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(.performDefaultHandling, nil)
  }
}
