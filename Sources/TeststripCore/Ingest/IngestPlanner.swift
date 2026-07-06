import Foundation

public enum ImportDestinationPolicy: String, Equatable, Sendable {
    case flat
    case capturedDate
}

public struct IngestPlan: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case addInPlace
        case copyToDestination
    }

    public var mode: Mode
    public var sourceRoot: URL
    public var destinationRoot: URL?
    public var destinationPolicy: ImportDestinationPolicy
    public var secondCopyDestination: URL?

    public init(
        mode: Mode,
        sourceRoot: URL,
        destinationRoot: URL? = nil,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil
    ) {
        self.mode = mode
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.destinationPolicy = destinationPolicy
        self.secondCopyDestination = secondCopyDestination
    }
}

public enum IngestPlanner {
    public static func addFolder(_ source: URL) -> IngestPlan {
        IngestPlan(mode: .addInPlace, sourceRoot: source, destinationRoot: nil)
    }

    public static func copyFromCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil
    ) -> IngestPlan {
        IngestPlan(
            mode: .copyToDestination,
            sourceRoot: source,
            destinationRoot: destinationRoot,
            destinationPolicy: destinationPolicy,
            secondCopyDestination: secondCopyDestination
        )
    }
}
