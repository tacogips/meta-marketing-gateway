import Foundation
import MetaGraphPrimitives

/// Closed typed builders make the only supported creation state immutable.
/// They do not grant transport eligibility; catalog policy still blocks every
/// mutation until all provider evidence and production composition contracts
/// have a dated review.
public enum PausedMutationBuilders {
  public static func campaign(
    account: String, name: String, objective: String, version: GraphAPIVersion
  ) throws -> GraphRequest {
    try create(
      account: account, edge: "campaigns", operationID: "meta.ads.campaign.create",
      version: version,
      fields: ["name": name, "objective": objective, "status": "PAUSED"])
  }

  public static func adSet(
    account: String, name: String, campaignID: String, version: GraphAPIVersion
  ) throws -> GraphRequest {
    try create(
      account: account, edge: "adsets", operationID: "meta.ads.adset.create", version: version,
      fields: ["name": name, "campaign_id": campaignID, "status": "PAUSED"])
  }

  public static func ad(
    account: String, name: String, adSetID: String, creativeID: String, version: GraphAPIVersion
  ) throws -> GraphRequest {
    try create(
      account: account, edge: "ads", operationID: "meta.ads.ad.create", version: version,
      fields: ["name": name, "adset_id": adSetID, "creative": creativeID, "status": "PAUSED"])
  }

  public static func creative(
    account: String, name: String, objectStorySpec: String, version: GraphAPIVersion
  ) throws -> GraphRequest {
    // Creative creation is explicitly non-serving: it has no status, budget,
    // bid, targeting, schedule, or activation carrier.
    try create(
      account: account, edge: "adcreatives", operationID: "meta.ads.adcreative.create",
      version: version, fields: ["name": name, "object_story_spec": objectStorySpec])
  }

  private static func create(
    account: String, edge: String, operationID: String, version: GraphAPIVersion,
    fields: [String: String]
  ) throws -> GraphRequest {
    guard account.wholeMatch(of: /act_[0-9]+/) != nil,
      fields.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4_096 }),
      fields.keys.allSatisfy({ $0.wholeMatch(of: /[a-z_]{1,64}/) != nil })
    else { throw GraphValidationError.policyDenied }
    let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    return try GraphRequest(
      method: .post, version: version, path: GraphPath(relative: "\(account)/\(edge)"),
      body: body, bodyMediaType: .json, operationID: operationID)
  }
}
