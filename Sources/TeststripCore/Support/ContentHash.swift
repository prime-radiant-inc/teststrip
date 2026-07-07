import Foundation
import CryptoKit

/// A content-identity digest for a file, used to recognize the same photo
/// wherever it lands in the catalog — a card re-inserted after more shooting,
/// or the same frame copied under a different name or folder.
///
/// Strategy — bounded partial hash (size + head chunk + tail chunk):
/// a modern RAW is tens of megabytes and a card holds thousands of them, so
/// hashing every byte of every file on import would read gigabytes to answer a
/// question a few kilobytes can. Instead the digest folds together the exact
/// file size and a fixed-size window from the head and the tail. The head
/// carries the format header, full EXIF, and (for RAW) the embedded preview;
/// the tail carries the end of the image payload; the exact size pins the
/// overall length. For real, distinct photographs those three together never
/// collide. The residual theoretical risk — two different files with identical
/// size, head, and tail but differing only in the unread middle — is resolved
/// where identity actually matters (before skipping a copy) by an exact byte
/// comparison against the candidate, so a partial-hash collision can never
/// silently drop a distinct file.
public enum ContentHash {
    /// 64 KiB head and 64 KiB tail. Comfortably spans a RAW header plus its
    /// embedded JPEG preview start while staying a trivially small read.
    public static let defaultChunkByteCount = 65_536

    public static func compute(forFileAt url: URL, chunkByteCount: Int = defaultChunkByteCount) throws -> String {
        let chunkByteCount = max(1, chunkByteCount)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw TeststripError.io("could not open \(url.path) for content hashing: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        do {
            let size = try fileSize(of: url)
            var hasher = SHA256()
            // Fold in the exact size first so two files sharing head and tail
            // but differing in length hash differently.
            withUnsafeBytes(of: UInt64(size).bigEndian) { hasher.update(bufferPointer: $0) }

            if size <= UInt64(chunkByteCount) * 2 {
                // Head and tail windows would overlap; hash the whole file so
                // any middle difference in a small file is still detected.
                hasher.update(data: try handle.readToEnd() ?? Data())
            } else {
                let head = try read(from: handle, at: 0, count: chunkByteCount)
                let tail = try read(from: handle, at: size - UInt64(chunkByteCount), count: chunkByteCount)
                hasher.update(data: head)
                hasher.update(data: tail)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch let error as TeststripError {
            throw error
        } catch {
            throw TeststripError.io("could not read \(url.path) for content hashing: \(error.localizedDescription)")
        }
    }

    private static func fileSize(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func read(from handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }
}
