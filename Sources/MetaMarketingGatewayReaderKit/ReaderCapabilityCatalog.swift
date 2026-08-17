import Foundation

public enum ReaderCapabilityCatalog {
  public static let json: String = {
    let operations = GeneratedReaderCapabilityCatalog.operations
      .map { "\"\($0)\"" }
      .joined(separator: ",")
    let availability = GeneratedReaderCapabilityCatalog.operations
      .map { "\"\($0)\":\"\(GeneratedReaderCapabilityCatalog.availabilityByOperation[$0]!)\"" }
      .joined(separator: ",")
    return
      "{\"ok\":true,\"surface\":\"reader\",\"schemaReviewDate\":\"\(GeneratedReaderCapabilityCatalog.reviewDate)\",\"typedVersion\":\"v25.0\",\"operations\":[\(operations)],\"availabilityByOperation\":{\(availability)}}"
  }()
}
