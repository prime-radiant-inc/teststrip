import CoreGraphics
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

public struct SmokeCatalogSeederResult: Equatable {
    public var catalogURL: URL
    public var previewCacheRoot: URL
    public var sourceImageCount: Int
    public var assetCount: Int
    public var cachedPreviewCount: Int

    public init(
        catalogURL: URL,
        previewCacheRoot: URL,
        sourceImageCount: Int,
        assetCount: Int,
        cachedPreviewCount: Int
    ) {
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
        self.sourceImageCount = sourceImageCount
        self.assetCount = assetCount
        self.cachedPreviewCount = cachedPreviewCount
    }
}

public struct SmokeCatalogSeeder {
    public var applicationSupportDirectory: URL
    public var count: Int

    private let renderedLevels: [PreviewLevel] = [.micro, .grid, .medium, .large]

    public init(applicationSupportDirectory: URL, count: Int) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.count = max(0, count)
    }

    public func run() throws -> SmokeCatalogSeederResult {
        let appRoot = applicationSupportDirectory.appendingPathComponent("Teststrip", isDirectory: true)
        let sourceRoot = appRoot.appendingPathComponent("SmokeOriginals", isDirectory: true)
        let catalogURL = appRoot.appendingPathComponent("catalog.sqlite")
        let previewCache = PreviewCache(root: appRoot.appendingPathComponent("Previews", isDirectory: true))

        if FileManager.default.fileExists(atPath: catalogURL.path) {
            throw TeststripError.invalidState("refusing to seed smoke catalog over existing catalog: \(catalogURL.path)")
        }

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewCache.root, withIntermediateDirectories: true)

        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let renderer = PreviewRenderer()
        var sourceImageCount = 0

        for index in 0..<count {
            let assetID = AssetID(rawValue: "smoke-\(index)")
            let sourceURL = sourceRoot.appendingPathComponent("\(assetID.rawValue).jpg")
            try Self.writeSmokeJPEG(to: sourceURL, index: index)
            sourceImageCount += 1

            try repository.upsert(asset(
                id: assetID,
                originalURL: sourceURL,
                index: index,
                fingerprint: fingerprint(for: sourceURL)
            ))

            for level in renderedLevels {
                try renderer.render(
                    sourceURL: sourceURL,
                    level: level,
                    destinationURL: previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
                )
            }
        }

        return SmokeCatalogSeederResult(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root,
            sourceImageCount: sourceImageCount,
            assetCount: try repository.assetCount(),
            cachedPreviewCount: try cachedPreviewCount(root: previewCache.root)
        )
    }

    private func asset(id: AssetID, originalURL: URL, index: Int, fingerprint: FileFingerprint) -> Asset {
        let colorLabels = ColorLabel.allCases
        let colorLabel = colorLabels[index % colorLabels.count]
        let capturedAt = Date(timeIntervalSince1970: 1_704_067_200 + TimeInterval(index * 900))
        return Asset(
            id: id,
            originalURL: originalURL,
            volumeIdentifier: "Smoke",
            fingerprint: fingerprint,
            availability: .online,
            metadata: AssetMetadata(
                rating: index % 6,
                colorLabel: colorLabel,
                flag: index.isMultiple(of: 5) ? .reject : (index.isMultiple(of: 3) ? .pick : nil),
                keywords: ["smoke", "batch-\(index / 6)"],
                caption: "Smoke frame \(index + 1)"
            ),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1200,
                pixelHeight: 800,
                cameraMake: "Teststrip",
                cameraModel: "SmokeCam \(index % 3 + 1)",
                lensModel: "\(35 + (index % 4) * 15)mm",
                isoSpeed: 100 + (index % 5) * 200,
                capturedAt: capturedAt,
                provenance: ProviderProvenance(
                    provider: "TeststripBench",
                    model: "SmokeCatalogSeeder",
                    version: "1",
                    settingsHash: "default"
                )
            )
        )
    }

    private func fingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return FileFingerprint(size: size, modificationDate: modificationDate)
    }

    private static func writeSmokeJPEG(to url: URL, index: Int) throws {
        let width = 1200
        let height = 800
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create smoke bitmap context")
        }

        let red = CGFloat((index % 5) + 1) / 5.0
        let green = CGFloat((index % 7) + 1) / 7.0
        let blue = CGFloat((index % 11) + 1) / 11.0
        context.setFillColor(CGColor(
            red: red * 0.65,
            green: green * 0.65,
            blue: blue * 0.65,
            alpha: 1.0
        ))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(CGColor(
            red: min(red + 0.25, 1.0),
            green: min(green + 0.15, 1.0),
            blue: min(blue + 0.1, 1.0),
            alpha: 1.0
        ))
        context.fill(CGRect(x: 80 + (index % 4) * 70, y: 90, width: 420, height: 260))
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.45))
        context.fill(CGRect(x: 620, y: 180 + (index % 5) * 35, width: 360, height: 380))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create smoke jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write smoke jpeg")
        }
    }

    private func cachedPreviewCount(root: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        let assetDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try assetDirectories.reduce(0) { count, assetDirectory in
            count + (try FileManager.default.contentsOfDirectory(
                at: assetDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "jpg" }.count)
        }
    }
}
