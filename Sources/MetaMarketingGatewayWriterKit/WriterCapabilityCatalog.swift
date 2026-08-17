import Foundation

/// Compiled writer projection. The catalog is intentionally conservative: the
/// known mutable routes are visible for offline planning but blocked from
/// preview/apply because their reviewed mutation, identity, reconciliation,
/// and authoritative non-billable proof contracts are incomplete.
public enum WriterCapabilityCatalog {
  public static let reviewDate = GeneratedWriterCapabilityCatalog.reviewDate
  public static let operations = GeneratedWriterCapabilityCatalog.operations
  public static let availabilityByOperation =
    GeneratedWriterCapabilityCatalog.availabilityByOperation
  public static let json: String = {
    let operations = Self.operations.map { "\"\($0)\"" }.joined(separator: ",")
    let availability = Self.operations
      .map { "\"\($0)\":\"\(Self.availabilityByOperation[$0]!)\"" }
      .joined(separator: ",")
    return
      "{\"ok\":true,\"surface\":\"writer\",\"schemaReviewDate\":\"\(Self.reviewDate)\",\"operations\":[\(operations)],\"availabilityByOperation\":{\(availability)}}"
  }()

  public static func allowsTransport(operationID: String) -> Bool {
    availabilityByOperation[operationID] == "enabled"
  }
}
