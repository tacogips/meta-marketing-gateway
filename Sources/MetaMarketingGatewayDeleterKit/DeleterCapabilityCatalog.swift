import Foundation

public enum DeleterCapabilityCatalog {
  public static let reviewDate = GeneratedDeleterCapabilityCatalog.reviewDate
  public static let operations = GeneratedDeleterCapabilityCatalog.operations
  public static let availabilityByOperation =
    GeneratedDeleterCapabilityCatalog.availabilityByOperation

  public static let json: String = {
    let operations = Self.operations.map { "\"\($0)\"" }.joined(separator: ",")
    let availability = Self.operations
      .map { "\"\($0)\":\"\(Self.availabilityByOperation[$0]!)\"" }
      .joined(separator: ",")
    return
      "{\"ok\":true,\"surface\":\"deleter\",\"schemaReviewDate\":\"\(Self.reviewDate)\",\"operations\":[\(operations)],\"availabilityByOperation\":{\(availability)}}"
  }()
}
