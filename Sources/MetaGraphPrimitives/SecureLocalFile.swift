import Darwin
import Foundation

public enum SecureFile {
  private static let maximumBytes = 1_048_576

  public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw GraphValidationError.invalidRequest }
    defer { close(descriptor) }

    var information = stat()
    guard fstat(descriptor, &information) == 0,
      (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == getuid(),
      information.st_size >= 0,
      information.st_size <= off_t(maximumBytes),
      (information.st_mode & (S_IWGRP | S_IWOTH)) == 0
    else { throw GraphValidationError.invalidRequest }

    var bytes = Data()
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      guard count >= 0 else { throw GraphValidationError.invalidRequest }
      if count == 0 { break }
      guard bytes.count + count <= maximumBytes else { throw GraphValidationError.invalidRequest }
      bytes.append(buffer, count: count)
    }
    return try JSONDecoder().decode(T.self, from: bytes)
  }

  public static func writeNew(_ bytes: Data, to url: URL) throws {
    guard bytes.count <= maximumBytes else { throw GraphValidationError.invalidRequest }
    let descriptor = open(
      url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw GraphValidationError.invalidRequest }
    var complete = false
    defer {
      close(descriptor)
      if !complete { try? FileManager.default.removeItem(at: url) }
    }
    var offset = 0
    while offset < bytes.count {
      let written = bytes.withUnsafeBytes { buffer in
        Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), bytes.count - offset)
      }
      guard written > 0 else { throw GraphValidationError.invalidRequest }
      offset += written
    }
    guard fsync(descriptor) == 0 else { throw GraphValidationError.invalidRequest }
    complete = true
  }

  /// Atomically replaces an already validated owner-only regular file using a
  /// sibling temporary file. Journal callers retain their own process lock.
  public static func replace(_ bytes: Data, at url: URL) throws {
    guard bytes.count <= maximumBytes else { throw GraphValidationError.invalidRequest }
    var existing = stat()
    guard lstat(url.path, &existing) == 0, (existing.st_mode & S_IFMT) == S_IFREG,
      existing.st_uid == getuid(), (existing.st_mode & (S_IWGRP | S_IWOTH)) == 0
    else { throw GraphValidationError.invalidRequest }
    let sibling = url.deletingLastPathComponent().appendingPathComponent(
      ".replace-\(UUID().uuidString)")
    try writeNew(bytes, to: sibling)
    guard rename(sibling.path, url.path) == 0 else {
      try? FileManager.default.removeItem(at: sibling)
      throw GraphValidationError.invalidRequest
    }
    try syncDirectory(containing: url)
  }

  /// Renames are durable only after the containing directory metadata is
  /// flushed. Callers use this after creating durable journal records too.
  public static func syncDirectory(containing url: URL) throws {
    let descriptor = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw GraphValidationError.invalidRequest }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else { throw GraphValidationError.invalidRequest }
  }
}
