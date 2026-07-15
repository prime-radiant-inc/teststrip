import Foundation

/// On-disk cache for contact reference photos, keyed by contact identifier.
/// The stored photo is the review-card reference image for a seeded contact.
public struct ContactPhotoCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    // Path-safe escaping is shared with PreviewCache via PathSafeName —
    // contact identifiers (e.g. `A:B/C`) get the same all-or-nothing,
    // byte-level hex encoding as asset directory names.
    public func url(for contactIdentifier: String) -> URL {
        root.appendingPathComponent("\(PathSafeName.encode(contactIdentifier)).jpg")
    }
}
