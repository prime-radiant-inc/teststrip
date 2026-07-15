import Foundation

/// On-disk cache for contact reference photos, keyed by contact identifier.
/// The stored photo is the review-card reference image for a seeded contact.
public struct ContactPhotoCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for contactIdentifier: String) -> URL {
        root.appendingPathComponent("\(Self.safeName(for: contactIdentifier)).jpg")
    }

    private static func safeName(for rawValue: String) -> String {
        var result = ""
        for scalar in rawValue.unicodeScalars {
            if (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z")
                || (scalar >= "0" && scalar <= "9") || scalar == "_" || scalar == "-" {
                result.unicodeScalars.append(scalar)
            } else {
                result += String(format: "~%04x", scalar.value)
            }
        }
        return result
    }
}
