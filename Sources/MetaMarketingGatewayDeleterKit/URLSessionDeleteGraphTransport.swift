import Foundation
import MetaGraphPrimitives

public struct URLSessionDeleteGraphTransport: DeleteGraphTransport {
  private static let maximumResponseBytes = 4_194_304
  private let configuration: URLSessionConfiguration

  public init() { configuration = Self.secureConfiguration() }
  init(configuration: URLSessionConfiguration) { self.configuration = configuration }

  public func send(_ request: DeleteGraphRequest, credential: DeleteGraphCredential) async throws
    -> GraphResponse
  {
    var outgoing = URLRequest(url: try request.url())
    outgoing.httpMethod = "DELETE"
    outgoing.timeoutInterval = 30
    credential.authorize(&outgoing)
    let session = URLSession(
      configuration: configuration, delegate: DeleteRedirectRejector(), delegateQueue: nil)
    let (bytes, response) = try await session.bytes(for: outgoing)
    guard let http = response as? HTTPURLResponse else { throw GraphValidationError.invalidRequest }
    var data = Data()
    for try await byte in bytes {
      guard data.count < Self.maximumResponseBytes else {
        throw GraphValidationError.invalidRequest
      }
      data.append(byte)
    }
    return try GraphResponse(status: http.statusCode, data: data)
  }

  private static func secureConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
  }
}

private final class DeleteRedirectRejector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
}
