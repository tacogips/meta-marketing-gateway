import Foundation

public struct GraphResponse: Sendable, Equatable {
  public let status: Int
  public let data: Data
  public init(status: Int, data: Data) throws {
    guard data.count <= 4_194_304 else { throw GraphValidationError.invalidRequest }
    self.status = status
    self.data = data
  }
}

public enum GraphErrorSanitizer {
  public static func sanitize(_ error: Error) -> String {
    if let safe = error as? GraphValidationError { return safe.localizedDescription }
    if let urlError = error as? URLError {
      return "transport failure (URLError \(urlError.errorCode))"
    }
    return "transport or provider failure"
  }
}
