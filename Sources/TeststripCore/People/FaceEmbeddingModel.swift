import CoreGraphics
import Foundation

/// A source of face-identity embeddings: an aligned 112×112 face image in,
/// a 512-d L2-normalized identity vector out. The concrete model sits behind
/// this protocol so a smaller/permissive model can drop in later without
/// downstream rework.
public protocol FaceEmbeddingModel: Sendable {
    var provenance: ProviderProvenance { get }
    func embedding(for alignedFace: CGImage) throws -> [Double]
}

public enum FaceEmbeddingModelError: Error {
    case modelUnavailable
    case inferenceFailed
}
