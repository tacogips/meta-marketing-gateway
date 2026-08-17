import Darwin
import Foundation
import MetaGraphPrimitives

/// A file handle for upload construction. It deliberately contains no provider
/// session state and is revalidated on every read to reject replacement races.
public struct GraphUploadFile: Sendable, Equatable {
  public let url: URL
  public let filename: String
  public let mediaType: String
  public let byteCount: Int
  private let device: UInt64
  private let inode: UInt64

  public init(url: URL, filename: String? = nil, mediaType: String = "application/octet-stream")
    throws
  {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw GraphValidationError.invalidRequest }
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
      info.st_uid == getuid(), info.st_size >= 0, info.st_size <= 16 * 1_024 * 1_024,
      (info.st_mode & (S_IWGRP | S_IWOTH)) == 0
    else { throw GraphValidationError.invalidRequest }
    let safeName = filename ?? url.lastPathComponent
    guard Self.safeFilename(safeName), Self.safeMediaType(mediaType) else {
      throw GraphValidationError.invalidRequest
    }
    self.url = url
    self.filename = safeName
    self.mediaType = mediaType
    byteCount = Int(info.st_size)
    device = UInt64(info.st_dev)
    inode = UInt64(info.st_ino)
  }

  public func read(offset: Int, maximumLength: Int) throws -> Data {
    guard offset >= 0, maximumLength > 0, maximumLength <= 1_048_576, offset <= byteCount else {
      throw GraphValidationError.invalidRequest
    }
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw GraphValidationError.invalidRequest }
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
      info.st_uid == getuid(), (info.st_mode & (S_IWGRP | S_IWOTH)) == 0,
      UInt64(info.st_dev) == device, UInt64(info.st_ino) == inode, Int(info.st_size) == byteCount
    else { throw GraphValidationError.invalidRequest }
    guard lseek(descriptor, off_t(offset), SEEK_SET) == off_t(offset) else {
      throw GraphValidationError.invalidRequest
    }
    let wanted = min(maximumLength, byteCount - offset)
    var result = Data(count: wanted)
    let actual = result.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, wanted) }
    guard actual >= 0 else { throw GraphValidationError.invalidRequest }
    result.removeSubrange(actual..<result.count)
    return result
  }

  private static func safeFilename(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 255 && !value.contains("/") && !value.contains("\\")
      && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }
  private static func safeMediaType(_ value: String) -> Bool {
    value.wholeMatch(of: /[A-Za-z0-9!#$&^_.+-]+\/[A-Za-z0-9!#$&^_.+-]+/) != nil
  }
}

public struct GraphMultipartPart: Sendable, Equatable {
  public let name: String
  public let value: String?
  public let file: GraphUploadFile?

  public init(name: String, value: String) throws {
    guard Self.safeName(name), value.utf8.count <= 64 * 1_024,
      value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { throw GraphValidationError.invalidRequest }
    self.name = name
    self.value = value
    file = nil
  }
  public init(name: String, file: GraphUploadFile) throws {
    guard Self.safeName(name) else { throw GraphValidationError.invalidRequest }
    self.name = name
    value = nil
    self.file = file
  }
  private static func safeName(_ value: String) -> Bool {
    value.wholeMatch(of: /[A-Za-z][A-Za-z0-9_-]{0,63}/) != nil
  }
}

/// Chunked multipart serialization. Callers pull chunks; it never reads an
/// entire source file into memory.
public struct GraphMultipartEncoder: Sendable {
  public let boundary: String
  public let parts: [GraphMultipartPart]
  public init(
    boundary: String = "MetaGatewayBoundary-" + UUID().uuidString, parts: [GraphMultipartPart]
  ) throws {
    guard boundary.wholeMatch(of: /[A-Za-z0-9-]{16,128}/) != nil, !parts.isEmpty, parts.count <= 32
    else {
      throw GraphValidationError.invalidRequest
    }
    self.boundary = boundary
    self.parts = parts
  }

  /// Produces a pull-based body. A consumer holds at most one file chunk,
  /// rather than an array containing the complete multipart payload.
  public func stream(maximumFileChunkBytes: Int = 64 * 1_024) throws -> GraphMultipartBodyStream {
    try GraphMultipartBodyStream(encoder: self, maximumFileChunkBytes: maximumFileChunkBytes)
  }

  fileprivate func header(for part: GraphMultipartPart) -> Data {
    var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part.name)\""
    if let file = part.file {
      header += "; filename=\"\(file.filename)\"\r\nContent-Type: \(file.mediaType)\r\n\r\n"
    } else if let value = part.value {
      header += "\r\n\r\n\(value)"
    }
    return Data(header.utf8)
  }
}

/// Thread-safe pull stream for an authenticated upload transport. It has no
/// persistence and reopens/revalidates the source file for every file chunk.
public final class GraphMultipartBodyStream: @unchecked Sendable {
  private enum Stage { case header, file, suffix, closing, complete }
  private let encoder: GraphMultipartEncoder
  private let maximumFileChunkBytes: Int
  private let lock = NSLock()
  private var partIndex = 0
  private var stage: Stage = .header
  private var fileOffset = 0
  private var emittedBytes = 0

  fileprivate init(encoder: GraphMultipartEncoder, maximumFileChunkBytes: Int) throws {
    guard (1...1_048_576).contains(maximumFileChunkBytes) else {
      throw GraphValidationError.invalidRequest
    }
    self.encoder = encoder
    self.maximumFileChunkBytes = maximumFileChunkBytes
  }

  /// Returns nil only after the closing boundary. Every returned value is
  /// bounded to one MiB and the aggregate multipart body to 32 MiB.
  public func nextChunk() throws -> Data? {
    lock.lock()
    defer { lock.unlock() }
    while true {
      switch stage {
      case .header:
        guard partIndex < encoder.parts.count else {
          stage = .closing
          continue
        }
        let part = encoder.parts[partIndex]
        stage = part.file == nil ? .suffix : .file
        return try record(encoder.header(for: part))
      case .file:
        guard let file = encoder.parts[partIndex].file else {
          throw GraphValidationError.invalidRequest
        }
        if fileOffset < file.byteCount {
          let bytes = try file.read(offset: fileOffset, maximumLength: maximumFileChunkBytes)
          guard !bytes.isEmpty else { throw GraphValidationError.invalidRequest }
          fileOffset += bytes.count
          return try record(bytes)
        }
        fileOffset = 0
        stage = .suffix
      case .suffix:
        partIndex += 1
        stage = .header
        return try record(Data("\r\n".utf8))
      case .closing:
        stage = .complete
        return try record(Data("--\(encoder.boundary)--\r\n".utf8))
      case .complete:
        return nil
      }
    }
  }

  private func record(_ data: Data) throws -> Data {
    guard data.count <= 1_048_576, emittedBytes <= 32 * 1_024 * 1_024 - data.count else {
      throw GraphValidationError.invalidRequest
    }
    emittedBytes += data.count
    return data
  }
}

/// Upload transport capabilities are intentionally separate from ordinary
/// Graph requests. The caller cannot provide an arbitrary upload origin.
public protocol GraphMultipartUploading: Sendable {
  func upload(
    path: GraphPath, version: GraphAPIVersion, boundary: String, body: GraphMultipartBodyStream,
    credential: GraphCredential
  ) async throws -> GraphResponse
}

public struct MetaGraphUploader: Sendable {
  private let transport: any GraphMultipartUploading
  private let credentials: any GraphCredentialResolving

  public init(
    transport: any GraphMultipartUploading,
    credentials: any GraphCredentialResolving = KinkoEnvironmentCredentials()
  ) {
    self.transport = transport
    self.credentials = credentials
  }

  /// The actual endpoint must be an approved Graph relative path; provider
  /// resumable-session routes remain disabled until revalidated.
  public func upload(
    path: GraphPath, version: GraphAPIVersion, encoder: GraphMultipartEncoder
  ) async throws -> GraphResponse {
    throw GraphValidationError.policyDenied
  }

  func uploadForTesting(
    path: GraphPath, version: GraphAPIVersion, encoder: GraphMultipartEncoder
  ) async throws -> GraphResponse {
    let stream = try encoder.stream()
    return try await transport.upload(
      path: path, version: version, boundary: encoder.boundary, body: stream,
      credential: credentials.resolve())
  }
}

public enum UploadSessionState: Sendable, Equatable {
  case ready
  case transferring(offset: Int)
  case completed, cancelled, failed
}

public protocol UploadSessionTransport: Sendable {
  func transfer(chunk: Data, offset: Int, totalBytes: Int) async throws -> Int
}

/// A protocol-only, in-memory resumable driver. There are intentionally no
/// concrete provider routes or persisted session identifiers until those routes
/// are officially revalidated.
public actor UploadSessionDriver {
  private var state: UploadSessionState = .ready
  public init() {}
  public func currentState() -> UploadSessionState { state }
  public func upload(
    file: GraphUploadFile, chunkBytes: Int = 256 * 1_024, transport: any UploadSessionTransport
  ) async throws {
    guard case .ready = state, (1...1_048_576).contains(chunkBytes) else {
      throw GraphValidationError.policyDenied
    }
    var offset = 0
    do {
      while offset < file.byteCount {
        try Task.checkCancellation()
        state = .transferring(offset: offset)
        let chunk = try file.read(offset: offset, maximumLength: chunkBytes)
        let next = try await transport.transfer(
          chunk: chunk, offset: offset, totalBytes: file.byteCount)
        guard next >= offset + chunk.count, next <= file.byteCount else {
          state = .failed
          throw GraphValidationError.invalidRequest
        }
        offset = next
      }
      state = .completed
    } catch is CancellationError {
      state = .cancelled
      throw CancellationError()
    } catch {
      state = .failed
      throw error
    }
  }
}
