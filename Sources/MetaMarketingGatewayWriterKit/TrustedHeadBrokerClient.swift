import Darwin
import Foundation
import MetaGraphPrimitives
import MetaTrustedHeadProtocol

/// Non-secret writer configuration for the independently supervised broker.
/// It has no storage path or fallback: the writer can name only a socket owned
/// by the distinct broker UID.
public struct TrustedHeadBrokerConfiguration: Sendable, Equatable {
  public let socketPath: String
  public let writerUID: UInt32
  public let brokerUID: UInt32

  public init(socketPath: String, writerUID: UInt32, brokerUID: UInt32) throws {
    guard socketPath.hasPrefix("/"), socketPath.utf8.count < 100, !socketPath.contains(".."),
      writerUID != brokerUID, uid_t(writerUID) == getuid()
    else { throw GraphValidationError.policyDenied }
    self.socketPath = socketPath
    self.writerUID = writerUID
    self.brokerUID = brokerUID
  }
}

/// Production-only broker client. It validates ownership before connecting and
/// authenticates the peer after connect. No directory, in-process fake, or
/// remote fallback can satisfy this client.
public actor UnixTrustedHeadBrokerClient: TrustedHeadClient {
  private let configuration: TrustedHeadBrokerConfiguration

  public init(configuration: TrustedHeadBrokerConfiguration) {
    self.configuration = configuration
  }

  public func readHead(namespace: String, recordIdentity: String) async throws -> TrustedHead? {
    let request = try TrustedHeadWireRequest(
      operation: "readHead", namespace: namespace, recordIdentity: recordIdentity)
    return try send(request).head
  }

  public func compareAndSetHead(
    namespace: String, recordIdentity: String, expected: TrustedHead?, proposed: TrustedHead
  ) async throws -> Bool {
    let request = try TrustedHeadWireRequest(
      operation: "compareAndSetHead", namespace: namespace, recordIdentity: recordIdentity,
      expected: expected, proposed: proposed)
    guard let result = try send(request).didCompareAndSet else {
      throw GraphValidationError.policyDenied
    }
    return result
  }

  private func send(_ request: TrustedHeadWireRequest) throws -> TrustedHeadWireResponse {
    try validateSocket()
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw GraphValidationError.policyDenied }
    defer { close(descriptor) }
    guard configureDeadline(descriptor) else { throw GraphValidationError.policyDenied }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = Array(configuration.socketPath.utf8) + [0]
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      destination.copyBytes(from: path)
    }
    let length = socklen_t(MemoryLayout<sa_family_t>.size + path.count)
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, length) }
    }
    guard connected == 0 else { throw GraphValidationError.policyDenied }
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(descriptor, &uid, &gid) == 0, uid == uid_t(configuration.brokerUID) else {
      throw GraphValidationError.policyDenied
    }
    try writeFrame(try JSONEncoder().encode(request), to: descriptor)
    let response = try JSONDecoder().decode(
      TrustedHeadWireResponse.self, from: readFrame(descriptor))
    guard response.schema == TrustedHeadWireResponse.schema else {
      throw GraphValidationError.policyDenied
    }
    return response
  }

  private func validateSocket() throws {
    var information = stat()
    let parent = URL(fileURLWithPath: configuration.socketPath).deletingLastPathComponent()
    guard lstat(configuration.socketPath, &information) == 0,
      (information.st_mode & S_IFMT) == S_IFSOCK,
      information.st_uid == uid_t(configuration.brokerUID),
      (information.st_mode & 0o077) == 0,
      Self.isSecureSocketDirectory(parent, owner: uid_t(configuration.brokerUID))
    else { throw GraphValidationError.policyDenied }
  }

  private func readFrame(_ descriptor: Int32) throws -> Data {
    let prefix = try readExactly(descriptor, count: 4)
    let length = decodeFrameLength(prefix)
    guard (1...8_192).contains(length) else { throw GraphValidationError.policyDenied }
    return try readExactly(descriptor, count: Int(length))
  }

  private func readExactly(_ descriptor: Int32, count: Int) throws -> Data {
    var result = Data(count: count)
    let received = result.withUnsafeMutableBytes { bytes -> Int in
      var offset = 0
      while offset < count {
        let readCount = Darwin.read(
          descriptor, bytes.baseAddress!.advanced(by: offset), count - offset)
        guard readCount > 0 else { return -1 }
        offset += readCount
      }
      return offset
    }
    guard received == count else { throw GraphValidationError.policyDenied }
    return result
  }

  private func writeFrame(_ data: Data, to descriptor: Int32) throws {
    guard data.count <= 8_192 else { throw GraphValidationError.policyDenied }
    var length = UInt32(data.count).bigEndian
    var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
    frame.append(data)
    try frame.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard written > 0 else { throw GraphValidationError.policyDenied }
        offset += written
      }
    }
  }

  private func decodeFrameLength(_ bytes: Data) -> UInt32 {
    bytes.reduce(UInt32.zero) { partial, byte in (partial << 8) | UInt32(byte) }
  }

  private static func isSecureSocketDirectory(_ url: URL, owner: uid_t) -> Bool {
    var information = stat()
    return lstat(url.path, &information) == 0 && (information.st_mode & S_IFMT) == S_IFDIR
      && information.st_uid == owner && (information.st_mode & 0o022) == 0
  }

  private func configureDeadline(_ descriptor: Int32) -> Bool {
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    let size = socklen_t(MemoryLayout<timeval>.size)
    let receive = withUnsafePointer(to: &timeout) {
      setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, size)
    }
    let send = withUnsafePointer(to: &timeout) {
      setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, size)
    }
    return receive == 0 && send == 0
  }
}
