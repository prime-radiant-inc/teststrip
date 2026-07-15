import Foundation

/// Path-safe name escaping shared by on-disk caches keyed by an arbitrary
/// identifier (asset IDs, contact IDs, ...). An identifier that is already
/// composed entirely of filesystem-safe characters passes through unchanged;
/// anything else is hex-encoded byte-for-byte so the result is always a
/// single safe path component.
enum PathSafeName {
    /// Encodes `raw` into a name safe to use as a single path component.
    /// If `raw` is non-empty and every UTF-8 byte is already safe
    /// (`[A-Za-z0-9_-]`), it is returned unchanged. Otherwise the entire
    /// value is hex-encoded byte-by-byte behind a `~` prefix — this is
    /// all-or-nothing, so callers never need to check which case applied.
    static func encode(_ raw: String) -> String {
        if !raw.isEmpty && raw.utf8.allSatisfy(isSafeByte) {
            return raw
        }

        var encoded = "~"

        for byte in raw.utf8 {
            let hex = String(byte, radix: 16, uppercase: true)
            if hex.count == 1 {
                encoded.append("0")
            }
            encoded.append(hex)
        }

        return encoded
    }

    private static func isSafeByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) ||
            (97...122).contains(byte) ||
            (48...57).contains(byte) ||
            byte == 45 ||
            byte == 95
    }
}
