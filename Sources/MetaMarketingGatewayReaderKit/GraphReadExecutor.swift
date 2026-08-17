import Foundation
import MetaGraphPrimitives

/// A narrow retry boundary: only validated GET requests are eligible for replay.
public protocol GraphSleeping: Sendable {
  func sleep(nanoseconds: UInt64) async throws
}

public protocol GraphRandomness: Sendable {
  func uniform(upperBound: UInt64) -> UInt64
}

public protocol GraphReadClock: Sendable {
  func nowNanoseconds() -> UInt64
}

public struct SystemGraphReadClock: GraphReadClock {
  public init() {}
  public func nowNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

public enum GraphReadEvent: Sendable, Equatable {
  case attempt(Int)
  case retrying(attempt: Int, delayNanoseconds: UInt64, reason: String)
  case terminal(attempt: Int, status: Int?)
  case budgetExhausted
}

public protocol GraphReadEventSink: Sendable {
  func record(_ event: GraphReadEvent) async
}

public struct DiscardingGraphReadEventSink: GraphReadEventSink {
  public init() {}
  public func record(_ event: GraphReadEvent) async {}
}

/// A shared actor can pace independent executors without making requests wait
/// while an actor lock is held. Production callers opt in by sharing one value.
public actor GraphReadThrottle {
  private var nextAllowedAt: UInt64 = 0
  private let minimumIntervalNanoseconds: UInt64

  public init(minimumIntervalNanoseconds: UInt64 = 0) throws {
    guard minimumIntervalNanoseconds <= 10_000_000_000 else {
      throw GraphValidationError.invalidRequest
    }
    self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
  }

  public func reserve(nowNanoseconds: UInt64) -> UInt64 {
    let reserved = max(nowNanoseconds, nextAllowedAt)
    let addition = reserved.addingReportingOverflow(minimumIntervalNanoseconds)
    nextAllowedAt = addition.overflow ? UInt64.max : addition.partialValue
    return reserved - nowNanoseconds
  }
}

public struct SystemGraphRandomness: GraphRandomness {
  public init() {}
  public func uniform(upperBound: UInt64) -> UInt64 {
    guard upperBound > 0 else { return 0 }
    return UInt64.random(in: 0...upperBound)
  }
}

public struct TaskGraphSleeper: GraphSleeping {
  public init() {}
  public func sleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}

public struct GraphReadRetryPolicy: Sendable, Equatable {
  public let maxAttempts: Int
  public let baseDelayNanoseconds: UInt64
  public let maximumDelayNanoseconds: UInt64
  public let maximumTotalDelayNanoseconds: UInt64
  public let maximumElapsedNanoseconds: UInt64

  public init(
    maxAttempts: Int = 3, baseDelayNanoseconds: UInt64 = 100_000_000,
    maximumDelayNanoseconds: UInt64 = 1_000_000_000,
    maximumTotalDelayNanoseconds: UInt64 = 2_000_000_000,
    maximumElapsedNanoseconds: UInt64 = 30_000_000_000
  ) throws {
    guard (1...5).contains(maxAttempts), baseDelayNanoseconds > 0,
      baseDelayNanoseconds <= maximumDelayNanoseconds,
      maximumDelayNanoseconds <= 5_000_000_000,
      maximumDelayNanoseconds <= maximumTotalDelayNanoseconds,
      maximumTotalDelayNanoseconds <= 10_000_000_000,
      maximumTotalDelayNanoseconds <= maximumElapsedNanoseconds,
      maximumElapsedNanoseconds <= 120_000_000_000
    else { throw GraphValidationError.invalidRequest }
    self.maxAttempts = maxAttempts
    self.baseDelayNanoseconds = baseDelayNanoseconds
    self.maximumDelayNanoseconds = maximumDelayNanoseconds
    self.maximumTotalDelayNanoseconds = maximumTotalDelayNanoseconds
    self.maximumElapsedNanoseconds = maximumElapsedNanoseconds
  }

  public func maximumDelay(forRetry retry: Int) -> UInt64 {
    let multiplier = UInt64(1) << UInt64(min(retry - 1, 5))
    return min(maximumDelayNanoseconds, baseDelayNanoseconds * multiplier)
  }

  /// Full jitter selects every value in the capped exponential window.
  public func delay(forRetry retry: Int, randomness: any GraphRandomness) -> UInt64 {
    randomness.uniform(upperBound: maximumDelay(forRetry: retry))
  }
}

public struct GraphReadReceipt: Sendable, Equatable {
  public let response: GraphResponse
  public let attempts: Int
  public let waitedNanoseconds: UInt64
  public let events: [GraphReadEvent]
}

public struct GraphReadExecutor: Sendable {
  private let transport: any ReaderGraphTransport
  private let sleeper: any GraphSleeping
  private let randomness: any GraphRandomness
  private let policy: GraphReadRetryPolicy
  private let clock: any GraphReadClock
  private let events: any GraphReadEventSink
  private let throttle: GraphReadThrottle?

  public init(
    transport: any ReaderGraphTransport, sleeper: any GraphSleeping = TaskGraphSleeper(),
    randomness: any GraphRandomness = SystemGraphRandomness(),
    policy: GraphReadRetryPolicy = try! GraphReadRetryPolicy(),
    clock: any GraphReadClock = SystemGraphReadClock(),
    events: any GraphReadEventSink = DiscardingGraphReadEventSink(),
    throttle: GraphReadThrottle? = nil
  ) {
    self.transport = transport
    self.sleeper = sleeper
    self.randomness = randomness
    self.policy = policy
    self.clock = clock
    self.events = events
    self.throttle = throttle
  }

  public func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
  {
    try await execute(request, credential: credential).response
  }

  public func execute(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphReadReceipt
  {
    var attempt = 1
    var waited: UInt64 = 0
    var evidence: [GraphReadEvent] = []
    let started = clock.nowNanoseconds()
    while true {
      try Task.checkCancellation()
      let now = clock.nowNanoseconds()
      guard now >= started, now - started <= policy.maximumElapsedNanoseconds else {
        await events.record(.budgetExhausted)
        throw GraphValidationError.invalidRequest
      }
      if let throttle {
        let throttleDelay = await throttle.reserve(nowNanoseconds: clock.nowNanoseconds())
        let throttledNow = clock.nowNanoseconds()
        guard throttledNow >= started,
          throttleDelay <= policy.maximumElapsedNanoseconds - (throttledNow - started)
        else {
          await events.record(.budgetExhausted)
          throw GraphValidationError.invalidRequest
        }
        if throttleDelay > 0 { try await sleeper.sleep(nanoseconds: throttleDelay) }
      }
      evidence.append(.attempt(attempt))
      await events.record(.attempt(attempt))
      do {
        let response = try await transport.send(request, credential: credential)
        guard Self.retryable(status: response.status), attempt < policy.maxAttempts else {
          let terminal = GraphReadEvent.terminal(attempt: attempt, status: response.status)
          evidence.append(terminal)
          await events.record(terminal)
          return GraphReadReceipt(
            response: response, attempts: attempt, waitedNanoseconds: waited, events: evidence)
        }
      } catch {
        guard Self.retryable(error: error), attempt < policy.maxAttempts else {
          let terminal = GraphReadEvent.terminal(attempt: attempt, status: nil)
          evidence.append(terminal)
          await events.record(terminal)
          throw error
        }
      }
      let delay = policy.delay(forRetry: attempt, randomness: randomness)
      guard waited <= policy.maximumTotalDelayNanoseconds - delay else {
        await events.record(.budgetExhausted)
        throw GraphValidationError.invalidRequest
      }
      let delayedNow = clock.nowNanoseconds()
      guard delayedNow >= started,
        delay <= policy.maximumElapsedNanoseconds - (delayedNow - started)
      else {
        await events.record(.budgetExhausted)
        throw GraphValidationError.invalidRequest
      }
      let event = GraphReadEvent.retrying(
        attempt: attempt, delayNanoseconds: delay, reason: "transient")
      evidence.append(event)
      await events.record(event)
      try await sleeper.sleep(nanoseconds: delay)
      waited += delay
      attempt += 1
    }
  }

  public static func retryable(status: Int) -> Bool {
    status == 429 || (500...599).contains(status)
  }

  public static func retryable(error: Error) -> Bool {
    guard let error = error as? URLError else { return false }
    return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost]
      .contains(error.code)
  }
}
