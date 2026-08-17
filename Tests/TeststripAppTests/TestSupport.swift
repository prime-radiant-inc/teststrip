import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore
@testable import TeststripApp

func makeTemporaryDirectory(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("teststrip-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func makeModelWithCatalogAssetsAndPreviewCache(
    named name: String,
    assets: [Asset],
    configureRepository: (CatalogRepository) throws -> Void = { _ in },
    workerSupervisor: WorkerSupervisor? = nil,
    seedsLargePreviews: Bool = false,
    backgroundWorkPublicationInterval: TimeInterval? = nil,
    backgroundWorkPublicationScheduler: any WorkerTimeoutScheduling = DispatchWorkerTimeoutScheduler()
) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
    let directory = try makeTemporaryDirectory(named: name)
    let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)
    try repository.upsert(assets)
    try configureRepository(repository)
    let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
    if seedsLargePreviews {
        for asset in assets {
            try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))
        }
    }
    let catalog = AppCatalog(
        paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
        repository: repository,
        previewCache: previewCache,
        importService: LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
            previewCache: previewCache
        )
    )
    let model = try AppModel.load(
        catalog: catalog,
        workerSupervisor: workerSupervisor,
        backgroundWorkPublicationInterval: backgroundWorkPublicationInterval,
        backgroundWorkPublicationScheduler: backgroundWorkPublicationScheduler
    )
    return (model, repository, previewCache)
}

func makeModelWithCatalogAssets(
    named name: String,
    assets: [Asset],
    configureRepository: (CatalogRepository) throws -> Void = { _ in },
    workerSupervisor: WorkerSupervisor? = nil,
    seedsLargePreviews: Bool = false
) throws -> (AppModel, CatalogRepository) {
    let result = try makeModelWithCatalogAssetsAndPreviewCache(
        named: name,
        assets: assets,
        configureRepository: configureRepository,
        workerSupervisor: workerSupervisor,
        seedsLargePreviews: seedsLargePreviews
    )
    return (result.model, result.repository)
}

/// Writes a small PNG whose pixel bytes vary with the destination path, so
/// each file has distinct content. Content-hash dedup would otherwise treat
/// same-byte files at different paths as duplicates of each other.
func writeTestPNG(to url: URL) throws {
    let pathHash = abs(url.path.hashValue)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TeststripError.io("could not create test bitmap context")
    }
    let red = CGFloat(pathHash % 256) / 255
    let green = CGFloat((pathHash / 256) % 256) / 255
    let blue = CGFloat((pathHash / 65536) % 256) / 255
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write test png")
    }
}

func writeDistinctTestPNG(to url: URL, tag: Int) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TeststripError.io("could not create test bitmap context")
    }
    let component = CGFloat(tag % 256) / 255
    context.setFillColor(CGColor(red: component, green: 0.4, blue: 0.8, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create distinct test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write distinct test png")
    }
}

func writePreviewPlaceholder(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("preview".utf8).write(to: url)
}
