import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// InsightFace `w600k_r50` ArcFace (ResNet50, 512-d) run on-device via Core ML.
/// Takes an aligned 112×112 face image and returns a 512-d L2-normalized
/// identity embedding.
public final class ArcFaceCoreMLModel: FaceEmbeddingModel, @unchecked Sendable {
    public static let modelFileName = "arcface-w600k-r50.mlpackage"

    public var provenance: ProviderProvenance {
        ProviderProvenance(provider: "face-recognition", model: "arcface-w600k-r50", version: "1", settingsHash: "default")
    }

    private let model: MLModel
    private let inputName: String
    private let inputWidth: Int
    private let inputHeight: Int

    /// Loads the model at `modelURL`. Returns nil when the model cannot be
    /// compiled or loaded (e.g. a corrupt or missing artifact), so evaluation
    /// can continue without face embeddings.
    public init?(modelURL: URL) {
        guard let loaded = Self.loadModel(at: modelURL) else { return nil }
        self.model = loaded
        guard let (name, description) = loaded.modelDescription.inputDescriptionsByName
            .first(where: { $0.value.type == .image }),
            let image = description.imageConstraint else {
            return nil
        }
        self.inputName = name
        self.inputWidth = image.pixelsWide
        self.inputHeight = image.pixelsHigh
    }

    /// Finds the bundled model: an explicit `TESTSTRIP_FACE_MODEL_PATH`
    /// override (tests), then `Bundle.main`, then the repo dev path
    /// `sample-data/models/arcface-w600k-r50.mlpackage` (so `swift test` from
    /// the package root exercises the real model). Returns nil when absent.
    public static func bundled() -> ArcFaceCoreMLModel? {
        for url in candidateURLs() where FileManager.default.fileExists(atPath: url.path) {
            if let model = ArcFaceCoreMLModel(modelURL: url) {
                return model
            }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let override = ProcessInfo.processInfo.environment["TESTSTRIP_FACE_MODEL_PATH"] {
            urls.append(URL(fileURLWithPath: override))
        }
        if let bundled = Bundle.main.url(forResource: "arcface-w600k-r50", withExtension: "mlpackage") {
            urls.append(bundled)
        }
        // Face embedding runs in the out-of-process worker, whose Bundle.main is
        // Contents/Helpers — not the app's Contents/Resources where the model is
        // bundled. Resolve the enclosing .app/Contents/Resources from the
        // executable path so both the app (Contents/MacOS) and the worker
        // (Contents/Helpers) find the same model.
        if let executable = Bundle.main.executableURL {
            let contentsResources = executable
                .deletingLastPathComponent()   // .../Contents/{MacOS,Helpers}
                .deletingLastPathComponent()   // .../Contents
                .appendingPathComponent("Resources/\(modelFileName)")
            urls.append(contentsResources)
        }
        let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("sample-data/models/\(modelFileName)")
        urls.append(devPath)
        return urls
    }

    private static func loadModel(at url: URL) -> MLModel? {
        do {
            let configuration = MLModelConfiguration()
            if url.pathExtension == "mlmodelc" {
                return try MLModel(contentsOf: url, configuration: configuration)
            }
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled, configuration: configuration)
        } catch {
            return nil
        }
    }

    public func embedding(for alignedFace: CGImage) throws -> [Double] {
        guard let pixelBuffer = Self.pixelBuffer(from: alignedFace, width: inputWidth, height: inputHeight) else {
            throw FaceEmbeddingModelError.inferenceFailed
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)])
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: input)
        } catch {
            throw FaceEmbeddingModelError.inferenceFailed
        }
        guard let multiArray = Self.firstMultiArray(in: prediction) else {
            throw FaceEmbeddingModelError.inferenceFailed
        }
        var vector = [Double](repeating: 0, count: multiArray.count)
        for index in 0..<multiArray.count {
            vector[index] = multiArray[index].doubleValue
        }
        return Self.l2Normalized(vector)
    }

    private static func firstMultiArray(in provider: MLFeatureProvider) -> MLMultiArray? {
        for name in provider.featureNames {
            if let array = provider.featureValue(for: name)?.multiArrayValue {
                return array
            }
        }
        return nil
    }

    private static func l2Normalized(_ vector: [Double]) -> [Double] {
        let magnitude = vector.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    private static func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32ARGB, attributes as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
