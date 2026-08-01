import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

public struct FaceStackFixtureSeederResult: Equatable {
    public var stackFilenames: [String]
    public var singleCount: Int
    public var stackCaptureGapSeconds: TimeInterval
    public var backgroundFaceProminence: Double

    public init(
        stackFilenames: [String],
        singleCount: Int,
        stackCaptureGapSeconds: TimeInterval,
        backgroundFaceProminence: Double
    ) {
        self.stackFilenames = stackFilenames
        self.singleCount = singleCount
        self.stackCaptureGapSeconds = stackCaptureGapSeconds
        self.backgroundFaceProminence = backgroundFaceProminence
    }
}

/// Writes the fixture the per-face report-card card needs: one folder where
/// four frames fall inside `AssetStackBuilder`'s capture window (so the burst
/// rail shows a real multi-frame stack) and everything else is hours apart
/// (so it stays a standalone stop). Two stack frames are real portraits; a
/// third is a composite carrying one subject face and one genuinely small
/// background face, so the prominence cap can be proved live; the fourth is
/// deliberately faceless, which is the card's falsification leg — a frame
/// with no faces must never get a rail dot.
///
/// The faces corpus itself carries no EXIF capture date, so the copies made
/// here get one written in. Originals in `sample-data/photos/faces` are never
/// modified.
public struct FaceStackFixtureSeeder {
    public static let stackFaceFilenames = ["stack-1-face.jpg", "stack-2-face.jpg"]
    public static let stackCompositeFilename = "stack-3-two-faces.jpg"
    public static let stackNoFaceFilename = "stack-4-noface.jpg"

    /// Portraits picked because both are single, well-lit, front-facing
    /// subjects that the live CIDetector pass reliably finds (`run()` asserts
    /// this, so a corpus change fails loudly instead of silently producing a
    /// faceless "face" stack).
    private static let stackSourceFilenames = [
        "commons-glenn-senator-portrait.jpg",
        "commons-ride-1984-portrait.jpg"
    ]

    /// Candidate widths for the composited background face, as a fraction of
    /// the subject frame's width. `run()` walks them smallest-first and keeps
    /// the first that CIDetector actually finds while still landing below
    /// `FaceReportGrading.prominenceFloor` — measured acceptance, not a
    /// guessed size.
    private static let backgroundWidthFractions = [0.06, 0.08, 0.10, 0.13, 0.16]

    /// 1s apart: comfortably inside the 2s window, and chained so all four
    /// frames land in one stack.
    private static let stackGapSeconds: TimeInterval = 1
    /// An hour apart: far outside the window, so every other photo is its own
    /// standalone stop.
    private static let singleGapSeconds: TimeInterval = 3600
    private static let baseCapture = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01T12:00:00Z

    public var directory: URL
    public var sourcePhotoDirectory: URL

    public init(directory: URL, sourcePhotoDirectory: URL) {
        self.directory = directory
        self.sourcePhotoDirectory = sourcePhotoDirectory
    }

    public func run() throws -> FaceStackFixtureSeederResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let analyzer = CoreImageFaceExpressionAnalyzer()

        var sourceURLs: [URL] = []
        for (index, sourceName) in Self.stackSourceFilenames.enumerated() {
            let sourceURL = sourcePhotoDirectory.appendingPathComponent(sourceName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw TeststripError.invalidState("face stack fixture source missing: \(sourceURL.path)")
            }
            sourceURLs.append(sourceURL)
            let destinationURL = directory.appendingPathComponent(Self.stackFaceFilenames[index])
            try Self.copyJPEG(
                from: sourceURL,
                to: destinationURL,
                capturedAt: Self.baseCapture.addingTimeInterval(Double(index) * Self.stackGapSeconds)
            )
            guard try !analyzer.detectFaces(previewURL: destinationURL).isEmpty else {
                throw TeststripError.invalidState("face stack fixture \(sourceName) yielded no detectable face")
            }
        }

        let compositeURL = directory.appendingPathComponent(Self.stackCompositeFilename)
        let backgroundProminence = try Self.writeComposite(
            subjectURL: sourceURLs[0],
            backgroundURL: sourceURLs[1],
            to: compositeURL,
            capturedAt: Self.baseCapture.addingTimeInterval(2 * Self.stackGapSeconds),
            analyzer: analyzer
        )

        let facelessURL = directory.appendingPathComponent(Self.stackNoFaceFilename)
        try BenchmarkImageFixtures.writeJPEG(to: facelessURL, index: 0)
        try Self.stampCapture(
            at: facelessURL,
            capturedAt: Self.baseCapture.addingTimeInterval(3 * Self.stackGapSeconds)
        )
        guard try analyzer.detectFaces(previewURL: facelessURL).isEmpty else {
            throw TeststripError.invalidState("the deliberately faceless stack frame grew a detectable face")
        }

        let remaining = try FileManager.default
            .contentsOfDirectory(at: sourcePhotoDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .filter { !Self.stackSourceFilenames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for (index, sourceURL) in remaining.enumerated() {
            try Self.copyJPEG(
                from: sourceURL,
                to: directory.appendingPathComponent(sourceURL.lastPathComponent),
                capturedAt: Self.baseCapture.addingTimeInterval(Double(index + 1) * Self.singleGapSeconds)
            )
        }

        return FaceStackFixtureSeederResult(
            stackFilenames: Self.stackFaceFilenames + [Self.stackCompositeFilename, Self.stackNoFaceFilename],
            singleCount: remaining.count,
            stackCaptureGapSeconds: Self.stackGapSeconds,
            backgroundFaceProminence: backgroundProminence
        )
    }

    /// Composites `backgroundURL` into the top-right corner of `subjectURL` at
    /// the smallest candidate size CIDetector still finds while staying below
    /// the prominence floor, and returns that background face's measured area
    /// fraction. Throws if no candidate satisfies both — a silently oversized
    /// "background" face would make the card's prominence-cap leg vacuous.
    private static func writeComposite(
        subjectURL: URL,
        backgroundURL: URL,
        to destinationURL: URL,
        capturedAt: Date,
        analyzer: CoreImageFaceExpressionAnalyzer
    ) throws -> Double {
        guard let subject = CIImage(contentsOf: subjectURL),
              let background = CIImage(contentsOf: backgroundURL) else {
            throw TeststripError.io("could not read composite fixture sources")
        }
        let context = CIContext()
        for fraction in backgroundWidthFractions {
            let scale = (subject.extent.width * fraction) / background.extent.width
            let scaled = background.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let inset = subject.extent.width * 0.04
            let placed = scaled.transformed(by: CGAffineTransform(
                translationX: subject.extent.maxX - scaled.extent.width - inset,
                y: subject.extent.maxY - scaled.extent.height - inset
            ))
            let composite = placed.composited(over: subject).cropped(to: subject.extent)
            guard let cgImage = context.createCGImage(composite, from: composite.extent),
                  let destination = CGImageDestinationCreateWithURL(
                    destinationURL as CFURL,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                  ) else {
                throw TeststripError.io("could not render composite fixture")
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw TeststripError.io("could not write composite fixture")
            }
            try stampCapture(at: destinationURL, capturedAt: capturedAt)

            let faces = try analyzer.detectFaces(previewURL: destinationURL)
            let areas = faces
                .map { Double($0.normalizedBounds.width * $0.normalizedBounds.height) }
                .sorted()
            if areas.count == 2,
               areas[0] < FaceReportGrading.prominenceFloor,
               areas[1] >= FaceReportGrading.prominenceFloor {
                return areas[0]
            }
        }
        throw TeststripError.invalidState(
            "no composite scale produced one subject face above and one background face below the prominence floor"
        )
    }

    /// Re-encodes the source's own compressed image data with an added EXIF
    /// capture date — the pixels the face detector sees are the originals'.
    private static func copyJPEG(from sourceURL: URL, to destinationURL: URL, capturedAt: Date) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TeststripError.io("could not read face stack fixture source \(sourceURL.lastPathComponent)")
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal] = exifTimestamp(capturedAt)
        properties[kCGImagePropertyExifDictionary] = exif
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw TeststripError.io("could not create face stack fixture \(destinationURL.lastPathComponent)")
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write face stack fixture \(destinationURL.lastPathComponent)")
        }
    }

    private static func stampCapture(at url: URL, capturedAt: Date) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try copyJPEG(from: url, to: temporaryURL, capturedAt: capturedAt)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }

    /// EXIF DateTimeOriginal is "yyyy:MM:dd HH:mm:ss" and
    /// `ImageIODecodeProvider` parses it as UTC.
    private static func exifTimestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d:%02d:%02d %02d:%02d:%02d",
            parts.year ?? 2026,
            parts.month ?? 1,
            parts.day ?? 1,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }
}
