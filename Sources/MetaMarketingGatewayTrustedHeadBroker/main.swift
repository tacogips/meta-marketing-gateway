import Darwin
import Foundation
import MetaTrustedHeadProtocol

private enum BrokerError: Error { case denied }

/// Supervision is intentionally explicit: the broker must run under its own
/// UID and accepts only the configured writer UID over a local Unix socket.
private struct BrokerConfiguration {
  let socketPath: String
  let stateDirectory: URL
  let writerUID: uid_t
  let brokerUID: uid_t

  init(arguments: [String]) throws {
    guard arguments.count == 8 else { throw BrokerError.denied }
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      guard ["--socket", "--state-dir", "--writer-uid", "--broker-uid"].contains(arguments[index]),
        index + 1 < arguments.count, values[arguments[index]] == nil
      else { throw BrokerError.denied }
      values[arguments[index]] = arguments[index + 1]
      index += 2
    }
    guard let socket = values["--socket"], let directory = values["--state-dir"],
      let writer = values["--writer-uid"].flatMap(UInt32.init),
      let broker = values["--broker-uid"].flatMap(UInt32.init),
      socket.utf8.count > 0, socket.utf8.count < 100,
      !socket.contains(".."), socket.hasPrefix("/"),
      writer != broker, uid_t(broker) == getuid()
    else { throw BrokerError.denied }
    socketPath = socket
    stateDirectory = URL(fileURLWithPath: directory, isDirectory: true)
    writerUID = uid_t(writer)
    brokerUID = uid_t(broker)
  }
}

private struct TrustedHeadStore {
  let directory: URL
  let owner: uid_t

  init(directory: URL, owner: uid_t) throws {
    guard Self.isSecureDirectory(directory, owner: owner) else { throw BrokerError.denied }
    self.directory = directory
    self.owner = owner
  }

  func read(namespace: String, recordIdentity: String) throws -> TrustedHead? {
    let url = try recordURL(namespace: namespace, recordIdentity: recordIdentity)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(TrustedHead.self, from: secureRead(url))
  }

  func compareAndSet(
    namespace: String, recordIdentity: String, expected: TrustedHead?, proposed: TrustedHead
  ) throws -> Bool {
    let url = try recordURL(namespace: namespace, recordIdentity: recordIdentity)
    let lock = try lockURL(namespace: namespace, recordIdentity: recordIdentity)
    let descriptor = open(lock.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else { throw BrokerError.denied }
    defer {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    let current = try read(namespace: namespace, recordIdentity: recordIdentity)
    guard current == expected else { return false }
    let nextSequence = (current?.sequence ?? 0) + 1
    guard proposed.sequence == nextSequence, proposed.digest != current?.digest else {
      throw BrokerError.denied
    }
    try atomicWrite(try JSONEncoder().encode(proposed), to: url)
    return true
  }

  private func recordURL(namespace: String, recordIdentity: String) throws -> URL {
    guard TrustedHeadWireRequest.isValidNamespace(namespace),
      TrustedHeadWireRequest.isDigest(recordIdentity)
    else { throw BrokerError.denied }
    return directory.appendingPathComponent("\(namespace)-\(recordIdentity).head")
  }

  private func lockURL(namespace: String, recordIdentity: String) throws -> URL {
    try recordURL(namespace: namespace, recordIdentity: recordIdentity).appendingPathExtension(
      "lock")
  }

  private func secureRead(_ url: URL) throws -> Data {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw BrokerError.denied }
    defer { close(descriptor) }
    var information = stat()
    guard fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == owner, information.st_size >= 0, information.st_size <= 4_096
    else { throw BrokerError.denied }
    let expectedCount = Int(information.st_size)
    var data = Data(count: expectedCount)
    let readCount = data.withUnsafeMutableBytes { bytes -> Int in
      var offset = 0
      while offset < expectedCount {
        let count = Darwin.read(
          descriptor, bytes.baseAddress!.advanced(by: offset), expectedCount - offset)
        guard count > 0 else { return -1 }
        offset += count
      }
      return offset
    }
    guard readCount == expectedCount else { throw BrokerError.denied }
    return data
  }

  private func atomicWrite(_ data: Data, to url: URL) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".head-\(UUID().uuidString)")
    let descriptor = open(
      temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw BrokerError.denied }
    defer {
      close(descriptor)
      _ = unlink(temporary.path)
    }
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard count > 0 else { throw BrokerError.denied }
        offset += count
      }
    }
    guard fsync(descriptor) == 0, rename(temporary.path, url.path) == 0 else {
      throw BrokerError.denied
    }
    let directoryFD = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard directoryFD >= 0 else { throw BrokerError.denied }
    defer { close(directoryFD) }
    guard fsync(directoryFD) == 0 else { throw BrokerError.denied }
  }

  fileprivate static func isSecureDirectory(_ url: URL, owner: uid_t) -> Bool {
    var information = stat()
    return lstat(url.path, &information) == 0 && (information.st_mode & S_IFMT) == S_IFDIR
      && information.st_uid == owner && (information.st_mode & 0o777) == 0o700
  }
}

private final class BrokerServer {
  private let configuration: BrokerConfiguration
  private let store: TrustedHeadStore

  init(configuration: BrokerConfiguration) throws {
    self.configuration = configuration
    store = try TrustedHeadStore(
      directory: configuration.stateDirectory, owner: configuration.brokerUID)
  }

  func run() throws -> Never {
    var existing = stat()
    let socketDirectory = URL(fileURLWithPath: configuration.socketPath).deletingLastPathComponent()
    guard lstat(configuration.socketPath, &existing) != 0,
      TrustedHeadStore.isSecureDirectory(socketDirectory, owner: configuration.brokerUID)
    else { throw BrokerError.denied }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw BrokerError.denied }
    defer { close(descriptor) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = Array(configuration.socketPath.utf8) + [0]
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      destination.copyBytes(from: path)
    }
    let length = socklen_t(MemoryLayout<sa_family_t>.size + path.count)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
    }
    guard bound == 0, chmod(configuration.socketPath, S_IRUSR | S_IWUSR) == 0,
      listen(descriptor, 16) == 0
    else { throw BrokerError.denied }
    while true {
      let client = accept(descriptor, nil, nil)
      guard client >= 0 else { continue }
      defer { close(client) }
      // A peer that sends only a frame prefix must not monopolize this
      // single-purpose service indefinitely.
      guard configureDeadline(client) else { continue }
      // One malformed or unauthorized local peer must not terminate the
      // broker service or alter another record's availability.
      try? serve(client)
    }
  }

  private func serve(_ descriptor: Int32) throws {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(descriptor, &uid, &gid) == 0, uid == configuration.writerUID else {
      throw BrokerError.denied
    }
    let requestData = try readFrame(descriptor)
    let request = try JSONDecoder().decode(TrustedHeadWireRequest.self, from: requestData)
      .validated()
    let response: TrustedHeadWireResponse
    if request.operation == "readHead" {
      if let head = try store.read(
        namespace: request.namespace, recordIdentity: request.recordIdentity)
      {
        response = TrustedHeadWireResponse(head: head)
      } else {
        response = TrustedHeadWireResponse()
      }
    } else {
      response = TrustedHeadWireResponse(
        didCompareAndSet: try store.compareAndSet(
          namespace: request.namespace, recordIdentity: request.recordIdentity,
          expected: request.expected, proposed: request.proposed!))
    }
    try writeFrame(try JSONEncoder().encode(response), to: descriptor)
  }

  private func readFrame(_ descriptor: Int32) throws -> Data {
    let prefix = try readExactly(descriptor, count: 4)
    let length = decodeFrameLength(prefix)
    guard (1...8_192).contains(length) else { throw BrokerError.denied }
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
    guard received == count else { throw BrokerError.denied }
    return result
  }

  private func writeFrame(_ data: Data, to descriptor: Int32) throws {
    guard data.count <= 8_192 else { throw BrokerError.denied }
    var length = UInt32(data.count).bigEndian
    var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
    frame.append(data)
    try frame.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard written > 0 else { throw BrokerError.denied }
        offset += written
      }
    }
  }

  private func decodeFrameLength(_ bytes: Data) -> UInt32 {
    bytes.reduce(UInt32.zero) { partial, byte in (partial << 8) | UInt32(byte) }
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

do {
  let configuration = try BrokerConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
  try BrokerServer(configuration: configuration).run()
} catch {
  FileHandle.standardError.write(
    Data("{\"ok\":false,\"error\":\"broker configuration or request denied\"}\n".utf8))
  exit(2)
}
