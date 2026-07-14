import Foundation

/// A recorded negative: the user confirmed a specific face is *not* this person,
/// so recognition must stop re-suggesting that person for that face.
public struct RejectedFacePerson: Hashable, Sendable {
    public var assetID: AssetID
    public var faceIndex: Int
    public var personID: String

    public init(assetID: AssetID, faceIndex: Int, personID: String) {
        self.assetID = assetID
        self.faceIndex = faceIndex
        self.personID = personID
    }
}
