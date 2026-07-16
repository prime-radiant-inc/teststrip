import Foundation

/// Pure pairing: given a set of assets (by id + original file URL), decide which
/// working-still files are secondaries of which RAW primary. Two assets bond when
/// they share a parent folder and a case-insensitive filename stem and one is a
/// RAW; the RAW is the primary and each working still becomes its secondary. A
/// RAW is never a secondary (we never hide original RAW bytes); a stem group with
/// no RAW produces no bonds.
enum AssetBondPlanner {
    struct BondInput: Equatable {
        let id: AssetID
        let originalURL: URL
    }

    /// Returns `secondaryID → primaryID` for every working still that bonds.
    static func bonds(for assets: [BondInput]) -> [AssetID: AssetID] {
        var groups: [String: [BondInput]] = [:]
        for asset in assets {
            let folder = asset.originalURL.deletingLastPathComponent().standardizedFileURL.path
            let stem = asset.originalURL.deletingPathExtension().lastPathComponent.lowercased()
            groups["\(folder)\n\(stem)", default: []].append(asset)
        }

        var bonds: [AssetID: AssetID] = [:]
        for group in groups.values {
            let raws = group
                .filter { isRaw($0.originalURL) }
                .sorted { $0.originalURL.path < $1.originalURL.path }
            guard let primary = raws.first else { continue }
            for asset in group where isWorkingStill(asset.originalURL) {
                bonds[asset.id] = primary.id
            }
        }
        return bonds
    }

    private static func isRaw(_ url: URL) -> Bool {
        ImageIODecodeProvider.rawExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isWorkingStill(_ url: URL) -> Bool {
        ImageIODecodeProvider.workingStillExtensions.contains(url.pathExtension.lowercased())
    }
}
