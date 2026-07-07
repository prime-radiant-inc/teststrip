import Foundation

public enum ImportDestinationPolicy: String, Equatable, Sendable {
    case flat
    case capturedDate
}

/// How an import treats a source file whose content is already in the catalog.
public enum DuplicateHandling: String, Equatable, Sendable {
    /// Copy and catalog every source file, even content that already exists —
    /// the user explicitly wants everything.
    case importAll
    /// Skip source files whose content is already cataloged, and collapse
    /// content that appears more than once within the same import batch.
    case skipCatalogedContent
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
    public var duplicateHandling: DuplicateHandling

    public init(
        mode: Mode,
        sourceRoot: URL,
        destinationRoot: URL? = nil,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil,
        duplicateHandling: DuplicateHandling = .importAll
    ) {
        self.mode = mode
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.destinationPolicy = destinationPolicy
        self.secondCopyDestination = secondCopyDestination
        self.duplicateHandling = duplicateHandling
    }
}

public enum IngestPlanner {
    public static func addFolder(
        _ source: URL,
        duplicateHandling: DuplicateHandling = .importAll
    ) -> IngestPlan {
        IngestPlan(
            mode: .addInPlace,
            sourceRoot: source,
            destinationRoot: nil,
            duplicateHandling: duplicateHandling
        )
    }

    public static func copyFromCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil,
        duplicateHandling: DuplicateHandling = .importAll
    ) -> IngestPlan {
        IngestPlan(
            mode: .copyToDestination,
            sourceRoot: source,
            destinationRoot: destinationRoot,
            destinationPolicy: destinationPolicy,
            secondCopyDestination: secondCopyDestination,
            duplicateHandling: duplicateHandling
        )
    }
}
