import Foundation

/// Moves a single file to the platform Trash, returning the URL it ended up
/// at. Injected so trash-mode relocation tests can substitute a fake writing
/// into a temp directory instead of touching the real Finder Trash.
public protocol Recycler: Sendable {
    func trash(_ url: URL) throws -> URL
}

/// Default `Recycler` backed by `FileManager.trashItem(at:resultingItemURL:)`
/// — the same mechanism Finder's "Move to Trash" uses, so trashed files are
/// recoverable via Finder "Put Back".
public struct FileManagerRecycler: Recycler {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            throw TeststripError.io("could not trash \(url.path): \(error.localizedDescription)")
        }
        guard let resultingURL = resultingURL as URL? else {
            throw TeststripError.io("trashing \(url.path) did not report a resulting Trash URL")
        }
        return resultingURL
    }
}
