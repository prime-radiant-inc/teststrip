import Foundation

public struct IngestPlan: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case addInPlace
        case copyToDestination
    }

    public var mode: Mode
    public var sourceRoot: URL
    public var destinationRoot: URL?

    public init(mode: Mode, sourceRoot: URL, destinationRoot: URL? = nil) {
        self.mode = mode
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
    }
}

public enum IngestPlanner {
    public static func addFolder(_ source: URL) -> IngestPlan {
        IngestPlan(mode: .addInPlace, sourceRoot: source, destinationRoot: nil)
    }

    public static func copyFromCard(source: URL, destinationRoot: URL) -> IngestPlan {
        IngestPlan(mode: .copyToDestination, sourceRoot: source, destinationRoot: destinationRoot)
    }
}
