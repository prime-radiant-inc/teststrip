import Foundation

/// One address-book contact that has a photo. `imageData` is the raw
/// `CNContact.imageData` (or thumbnail) bytes.
public struct ContactRecord: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let imageData: Data

    public init(identifier: String, name: String, imageData: Data) {
        self.identifier = identifier
        self.name = name
        self.imageData = imageData
    }
}

/// The seam over the address book. The live conformer wraps `CNContactStore`
/// (app target); tests supply a stub.
public protocol ContactsProviding: Sendable {
    func contactsWithPhotos() throws -> [ContactRecord]
}
