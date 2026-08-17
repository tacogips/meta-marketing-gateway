import Foundation

enum CapabilitySurface: String, Codable, Equatable, Sendable {
  case reader
  case writer
  case deleter
}

enum CapabilityKind: String, Codable, Equatable, Sendable {
  case publicRead
  case mutation
}

enum CapabilityMethod: String, Codable, Equatable, Sendable {
  case get = "GET"
  case post = "POST"
  case delete = "DELETE"
}

enum CapabilityImplementation: String, Codable, Equatable, Sendable {
  case typed
  case generic
  case planned
}

enum CapabilityAvailability: String, Codable, Equatable, Sendable {
  case enabled
  case denied
  case blockedVersionReview
  case blockedProviderProof
}

enum CapabilityBlocker: String, Codable, Equatable, Hashable, Sendable {
  case rolloutPolicy
  case missingMutationContract
  case missingPrincipalIdentityContract
  case missingReconcilerContract
  case missingMachineVerifiableAssetClassification
}

struct CapabilityOperation: Codable, Sendable {
  let id: String
  let surface: CapabilitySurface
  let kind: CapabilityKind
  let method: CapabilityMethod
  let path: String
  let version: String
  let implementation: CapabilityImplementation
  let reviewDate: String
  let source: String
  let availability: CapabilityAvailability
  let reason: String?
  let blockers: [CapabilityBlocker]?
}

struct CapabilityManifest: Codable, Sendable {
  let schema: Int
  let reviewDate: String
  let source: String
  let operations: [CapabilityOperation]
}

enum CatalogGenerationError: Error { case invalidManifest, invalidArguments }

enum CatalogGenerator {
  /// This catalog revision was reviewed against the accepted Meta contract on
  /// this exact date. A changed review date is a new catalog revision, not a
  /// caller-selectable relaxation of the release gate.
  private static let acceptedReviewDate = "2026-08-15"
  private static let providerProofBlocker =
    CapabilityBlocker.missingMachineVerifiableAssetClassification
  private static let rolloutPolicyBlocker = CapabilityBlocker.rolloutPolicy

  static func load(_ data: Data) throws -> CapabilityManifest {
    let manifest = try JSONDecoder().decode(CapabilityManifest.self, from: data)
    let ids = manifest.operations.map(\.id)
    guard manifest.schema == 1,
      manifest.reviewDate == acceptedReviewDate,
      let source = URL(string: manifest.source), source.scheme == "https",
      source.host == "developers.facebook.com", !manifest.operations.isEmpty,
      Set(ids).count == ids.count,
      manifest.operations.allSatisfy({
        isValid($0, manifestReviewDate: manifest.reviewDate)
      })
    else { throw CatalogGenerationError.invalidManifest }
    return manifest
  }

  private static func isValid(
    _ operation: CapabilityOperation, manifestReviewDate: String
  ) -> Bool {
    guard operation.id.wholeMatch(of: /meta\.[a-z0-9.-]{3,127}/) != nil,
      operation.path.wholeMatch(of: /[A-Za-z0-9_{}.\/-]{1,256}/) != nil,
      operation.version == "validated"
        || operation.version.wholeMatch(of: /v[0-9]{2}\.[0-9]/) != nil,
      operation.reviewDate == manifestReviewDate,
      let source = URL(string: operation.source), source.scheme == "https",
      source.host == "developers.facebook.com"
    else { return false }
    if operation.surface == .reader {
      return operation.kind == .publicRead && operation.method == .get && operation.reason == nil
        && operation.blockers == nil
    }
    guard operation.kind == .mutation,
      operation.surface == .writer ? operation.method == .post : operation.method == .delete,
      operation.reason?.utf8.count ?? 0 <= 1_024,
      let blockers = operation.blockers,
      blockers.count <= 16,
      Set(blockers).count == blockers.count
    else { return false }
    switch operation.availability {
    case .enabled:
      return operation.implementation != .planned && operation.reason == nil && blockers.isEmpty
    case .blockedProviderProof:
      return operation.implementation != .planned
        && operation.reason?.localizedCaseInsensitiveContains("authoritative") == true
        && blockers == [providerProofBlocker]
    case .blockedVersionReview, .denied:
      guard operation.reason?.isEmpty == false, !blockers.isEmpty else { return false }
      if operation.availability == .denied {
        return blockers.contains(rolloutPolicyBlocker)
      }
      // Version review is the only valid non-policy state when any contract
      // other than the authoritative asset-proof classifier remains open.
      return !blockers.contains(rolloutPolicyBlocker)
        && blockers.contains(where: { $0 != providerProofBlocker })
    }
  }

  static func swiftProjection(manifest: CapabilityManifest, surface: String) throws -> String {
    guard let selectedSurface = CapabilitySurface(rawValue: surface) else {
      throw CatalogGenerationError.invalidArguments
    }
    let operations = manifest.operations
      .filter { $0.surface == selectedSurface }
      .sorted { $0.id < $1.id }
    guard !operations.isEmpty,
      selectedSurface != .reader || operations.allSatisfy({ $0.method == .get }),
      selectedSurface != .writer || operations.allSatisfy({ $0.method == .post }),
      selectedSurface != .deleter || operations.allSatisfy({ $0.method == .delete })
    else { throw CatalogGenerationError.invalidManifest }
    let identifiers = operations.map { "\"\($0.id)\"" }.joined(separator: ", ")
    let availability = operations.map { "\"\($0.id)\": \"\($0.availability.rawValue)\"" }
      .joined(separator: ", ")
    let reviewDates = operations.map { "\"\($0.id)\": \"\($0.reviewDate)\"" }
      .joined(separator: ", ")
    let sources = operations.map { "\"\($0.id)\": \"\($0.source)\"" }
      .joined(separator: ", ")
    return """
      // Generated from Catalog/meta-capabilities.json; do not edit.
      import Foundation

      enum Generated\(selectedSurface.rawValue.capitalized)CapabilityCatalog {
        static let reviewDate = "\(manifest.reviewDate)"
        static let operations = [\(identifiers)]
        static let availabilityByOperation = [\(availability)]
        static let reviewDateByOperation = [\(reviewDates)]
        static let sourceByOperation = [\(sources)]
      }
      """ + "\n"
  }

  static func documentation(manifest: CapabilityManifest) -> String {
    let rows = manifest.operations.sorted { $0.id < $1.id }.map {
      "| `\($0.id)` | \($0.surface.rawValue) | \($0.availability.rawValue) | \($0.reviewDate) | \($0.source) |"
    }.joined(separator: "\n")
    return """
      # Capability catalog

      Reviewed \(manifest.reviewDate). `Catalog/meta-capabilities.json` is the source inventory.

      Reader operations are GET-only, Writer operations are POST-only, and Deleter operations
      are DELETE-only. Generic relative paths preserve Graph API coverage without sharing an
      HTTP-method capability across clients.

      | Operation | Surface | Availability | Reviewed | Official source |
      | --- | --- | --- | --- | --- |
      \(rows)
      """ + "\n"
  }
}

func write(_ text: String, to path: String) throws {
  try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
  guard arguments.count >= 4, arguments[0] == "--input" else {
    throw CatalogGenerationError.invalidArguments
  }
  let manifest = try CatalogGenerator.load(Data(contentsOf: URL(fileURLWithPath: arguments[1])))
  if arguments.count == 6, arguments[2] == "--surface", arguments[4] == "--swift-output" {
    try write(
      try CatalogGenerator.swiftProjection(manifest: manifest, surface: arguments[3]),
      to: arguments[5])
  } else if arguments.count == 4, arguments[2] == "--documentation-output" {
    try write(CatalogGenerator.documentation(manifest: manifest), to: arguments[3])
  } else {
    throw CatalogGenerationError.invalidArguments
  }
} catch {
  exit(2)
}
