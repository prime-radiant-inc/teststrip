import Foundation

/// Maps a Euclidean distance between L2-normalized AuraFace-v1 face embeddings
/// to a 0–100 "similarity %". For unit vectors, cosine similarity
/// `s = 1 − d²/2`; negative cosine (distance > √2) clamps to 0.
public enum FaceSimilarity {
    public static func percent(distance: Double) -> Int {
        let cosine = 1.0 - (distance * distance) / 2.0
        let clamped = min(max(cosine, 0), 1)
        return Int((clamped * 100).rounded())
    }
}
