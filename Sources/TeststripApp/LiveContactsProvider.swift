import Contacts
import Foundation
import TeststripCore

/// Live `CNContactStore`-backed contacts. `contactsWithPhotos()` fetches every
/// contact that has image data and returns `(identifier, name, imageData)`.
public struct LiveContactsProvider: ContactsProviding {
    public init() {}

    public func contactsWithPhotos() throws -> [ContactRecord] {
        let store = CNContactStore()
        // CNContactFormatter accesses several name components (middleName,
        // prefix, nickname, phonetic names, …); reading any un-fetched property
        // on a CNContact throws CNContactPropertyNotFetchedException. Its own
        // required-key descriptor covers exactly what the formatter touches, so
        // include it alongside the identifier/image keys we read directly.
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
        var records: [ContactRecord] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: request) { contact, _ in
            guard contact.imageDataAvailable, let data = contact.imageData else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            records.append(ContactRecord(identifier: contact.identifier, name: name, imageData: data))
        }
        return records
    }
}
