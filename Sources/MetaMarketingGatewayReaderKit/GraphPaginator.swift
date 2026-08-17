import Foundation
import MetaGraphPrimitives

public struct GraphPageBudget: Sendable, Equatable {
  public let maxPages: Int
  public let maxItems: Int
  public let maxBytes: Int
  public let maximumElapsedNanoseconds: UInt64

  public init(
    maxPages: Int = 10, maxItems: Int = 5_000, maxBytes: Int = 4_194_304,
    maximumElapsedNanoseconds: UInt64 = 30_000_000_000
  ) throws {
    guard (1...100).contains(maxPages), (1...100_000).contains(maxItems),
      (1...67_108_864).contains(maxBytes), (1...120_000_000_000).contains(maximumElapsedNanoseconds)
    else {
      throw GraphValidationError.invalidPagination
    }
    self.maxPages = maxPages
    self.maxItems = maxItems
    self.maxBytes = maxBytes
    self.maximumElapsedNanoseconds = maximumElapsedNanoseconds
  }
}

public enum GraphPaginator {
  /// Traverses only opaque `after` cursors supplied by an already-validated page envelope.
  public static func collect<Item: Sendable>(
    initial: PageRequest = try! PageRequest(), budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock(),
    fetch: @Sendable (PageRequest) async throws -> GraphPage<Item>
  ) async throws -> [Item] {
    var request = initial
    var seen = Set<String>()
    var result: [Item] = []
    var receivedBytes = 0
    let started = clock.nowNanoseconds()
    for _ in 0..<budget.maxPages {
      try Task.checkCancellation()
      let now = clock.nowNanoseconds()
      guard now >= started, now - started <= budget.maximumElapsedNanoseconds else {
        throw GraphValidationError.invalidPagination
      }
      let page = try await fetch(request)
      // A fetch is untrusted work too: do not return a final page that arrived
      // after the caller's deadline.
      let completedAt = clock.nowNanoseconds()
      guard completedAt >= started,
        completedAt - started <= budget.maximumElapsedNanoseconds
      else { throw GraphValidationError.invalidPagination }
      guard page.receivedBytes >= 0 else { throw GraphValidationError.invalidPagination }
      guard result.count + page.data.count <= budget.maxItems else {
        throw GraphValidationError.invalidPagination
      }
      // Validate the untrusted page count before subtraction. `GraphPage` is a
      // public envelope, so callers can construct it independently of transport.
      guard page.receivedBytes <= budget.maxBytes - receivedBytes else {
        throw GraphValidationError.invalidPagination
      }
      result.append(contentsOf: page.data)
      receivedBytes += page.receivedBytes
      guard let after = page.after else { return result }
      guard seen.insert(after.value).inserted else { throw GraphValidationError.invalidPagination }
      request = try PageRequest(limit: request.limit, direction: .after(after))
    }
    throw GraphValidationError.invalidPagination
  }
}
