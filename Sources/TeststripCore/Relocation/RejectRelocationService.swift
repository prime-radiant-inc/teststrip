import Foundation

public struct RejectRelocationMoveResult: Equatable, Sendable {
    public var originalFrom: URL
    public var originalTo: URL
    public var sidecarFrom: URL?
    public var sidecarTo: URL?

    public init(originalFrom: URL, originalTo: URL, sidecarFrom: URL?, sidecarTo: URL?) {
        self.originalFrom = originalFrom
        self.originalTo = originalTo
        self.sidecarFrom = sidecarFrom
        self.sidecarTo = sidecarTo
    }
}

/// Moves one reject original and its adjacent XMP sidecar together, rolling the
/// sidecar back if the original move fails so a partial run never orphans a
/// sidecar or half-moves a pair.
public struct RejectRelocationService: Sendable {
    private let sidecarStore = XMPSidecarStore()

    public init() {}

    public func move(originalFrom: URL, originalTo: URL) throws -> RejectRelocationMoveResult {
        let sidecarFrom = sidecarStore.existingSidecarURL(forOriginalAt: originalFrom)
        let sidecarTo = sidecarFrom == nil ? nil : sidecarStore.sidecarURL(forOriginalAt: originalTo)
        try createDirectory(at: originalTo.deletingLastPathComponent())

        if let sidecarFrom, let sidecarTo {
            try moveItem(from: sidecarFrom, to: sidecarTo)
        }
        do {
            try moveItem(from: originalFrom, to: originalTo)
        } catch {
            if let sidecarFrom, let sidecarTo {
                try? FileManager.default.moveItem(at: sidecarTo, to: sidecarFrom)
            }
            throw error
        }
        return RejectRelocationMoveResult(
            originalFrom: originalFrom,
            originalTo: originalTo,
            sidecarFrom: sidecarFrom,
            sidecarTo: sidecarTo
        )
    }

    public func moveBack(_ entry: RelocationManifestEntry) throws {
        try createDirectory(at: entry.originalFrom.deletingLastPathComponent())
        if let sidecarTo = entry.sidecarTo, let sidecarFrom = entry.sidecarFrom,
           FileManager.default.fileExists(atPath: sidecarTo.path) {
            try moveItem(from: sidecarTo, to: sidecarFrom)
        }
        guard FileManager.default.fileExists(atPath: entry.originalTo.path) else { return }
        try moveItem(from: entry.originalTo, to: entry.originalFrom)
    }

    private func createDirectory(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create relocation directory \(url.path): \(error.localizedDescription)")
        }
    }

    private func moveItem(from: URL, to: URL) throws {
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            throw TeststripError.io("could not move \(from.path) to \(to.path): \(error.localizedDescription)")
        }
    }
}
