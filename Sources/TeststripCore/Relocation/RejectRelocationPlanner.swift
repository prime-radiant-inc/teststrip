import Foundation

public struct RejectRelocationPlan: Equatable, Sendable {
    public var originalFrom: URL
    public var originalTo: URL

    public init(originalFrom: URL, originalTo: URL) {
        self.originalFrom = originalFrom
        self.originalTo = originalTo
    }
}

/// Maps reject originals to destination URLs beneath `destinationRoot`,
/// preserving each file's path relative to the moved set's longest common
/// ancestor directory, with case-insensitive collision disambiguation. Pure:
/// no filesystem side effects.
public struct RejectRelocationPlanner: Sendable {
    public var destinationRoot: URL

    public init(destinationRoot: URL) {
        self.destinationRoot = destinationRoot
    }

    public func plan(originals: [URL]) -> [RejectRelocationPlan] {
        guard !originals.isEmpty else { return [] }
        let ancestorComponents = Self.commonAncestorComponents(of: originals)
        var claimedNames: Set<String> = []
        return originals.map { original in
            let relativeComponents = Array(original.standardizedFileURL.pathComponents.dropFirst(ancestorComponents.count))
            let destination = Self.disambiguatedURL(
                base: destinationRoot,
                relativeComponents: relativeComponents,
                claimedNames: &claimedNames
            )
            return RejectRelocationPlan(originalFrom: original, originalTo: destination)
        }
    }

    private static func commonAncestorComponents(of originals: [URL]) -> [String] {
        let directoryComponentLists = originals.map {
            $0.standardizedFileURL.deletingLastPathComponent().pathComponents
        }
        guard var shared = directoryComponentLists.first else { return [] }
        for components in directoryComponentLists.dropFirst() {
            var prefixLength = 0
            while prefixLength < shared.count,
                  prefixLength < components.count,
                  shared[prefixLength] == components[prefixLength] {
                prefixLength += 1
            }
            shared = Array(shared.prefix(prefixLength))
        }
        return shared
    }

    private static func disambiguatedURL(
        base: URL,
        relativeComponents: [String],
        claimedNames: inout Set<String>
    ) -> URL {
        let directoryComponents = relativeComponents.dropLast()
        var directory = base
        for component in directoryComponents {
            directory = directory.appendingPathComponent(component, isDirectory: true)
        }
        let filename = relativeComponents.last ?? ""
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = filename
        var suffix = 2
        while claimedNames.contains(candidate.lowercased())
            || FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            suffix += 1
        }
        claimedNames.insert(candidate.lowercased())
        return directory.appendingPathComponent(candidate)
    }
}
