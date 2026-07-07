import Foundation

public struct FaceEmbedding: Equatable, Sendable {
    public var faceID: FaceID
    public var vector: [Double]

    public init(faceID: FaceID, vector: [Double]) {
        self.faceID = faceID
        self.vector = vector
    }
}

public struct FaceMatchSuggestion: Equatable, Sendable {
    public var personID: String
    public var faceIDs: [FaceID]

    public init(personID: String, faceIDs: [FaceID]) {
        self.personID = personID
        self.faceIDs = faceIDs
    }
}

public struct FaceClusterSuggestion: Equatable, Sendable {
    public var faceIDs: [FaceID]

    public init(faceIDs: [FaceID]) {
        self.faceIDs = faceIDs
    }
}

public struct FaceSuggestions: Equatable, Sendable {
    public var matches: [FaceMatchSuggestion]
    public var clusters: [FaceClusterSuggestion]

    public init(matches: [FaceMatchSuggestion] = [], clusters: [FaceClusterSuggestion] = []) {
        self.matches = matches
        self.clusters = clusters
    }
}

public struct FaceSuggestionBuilder: Sendable {
    // Calibrated to L2-normalized ArcFace (w600k_r50) identity embeddings.
    // For unit vectors, Euclidean distance d relates to cosine similarity s by
    // d = √(2 − 2s): same-person ArcFace cosine ≳ 0.4 → d ≲ 1.10, while
    // different people sit at cosine ≲ 0.2 → d ≳ 1.26. 1.10 is the tightest
    // value that keeps same-person faces together without merging distinct
    // identities; re-derived from the astronaut corpus (FaceCorpusGroupingTests).
    public static let defaultMaximumMatchDistance = 1.10
    public static let defaultMaximumClusterDistance = 1.10
    public static let defaultMinimumClusterFaceCount = 2

    public var maximumMatchDistance: Double
    public var maximumClusterDistance: Double
    public var minimumClusterFaceCount: Int

    public init(
        maximumMatchDistance: Double = Self.defaultMaximumMatchDistance,
        maximumClusterDistance: Double = Self.defaultMaximumClusterDistance,
        minimumClusterFaceCount: Int = Self.defaultMinimumClusterFaceCount
    ) {
        self.maximumMatchDistance = maximumMatchDistance
        self.maximumClusterDistance = maximumClusterDistance
        self.minimumClusterFaceCount = minimumClusterFaceCount
    }

    public func suggestions(
        unassignedFaces: [FaceEmbedding],
        confirmedFacesByPerson: [String: [[Double]]]
    ) -> FaceSuggestions {
        let normalizedFaces: [(faceID: FaceID, vector: [Double])] = unassignedFaces
            .compactMap { face in
                Self.normalized(face.vector).map { (faceID: face.faceID, vector: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.faceID.assetID.rawValue != rhs.faceID.assetID.rawValue {
                    return lhs.faceID.assetID.rawValue < rhs.faceID.assetID.rawValue
                }
                return lhs.faceID.faceIndex < rhs.faceID.faceIndex
            }
        let centroidsByPerson = confirmedFacesByPerson.compactMapValues(Self.centroid)

        var matchedFaceIDsByPerson: [String: [FaceID]] = [:]
        var unmatchedFaces: [(faceID: FaceID, vector: [Double])] = []
        for face in normalizedFaces {
            let nearest = centroidsByPerson
                .compactMap { personID, centroid in
                    Self.distance(face.vector, centroid).map { (personID: personID, distance: $0) }
                }
                .min { lhs, rhs in
                    if lhs.distance != rhs.distance {
                        return lhs.distance < rhs.distance
                    }
                    return lhs.personID < rhs.personID
                }
            if let nearest, nearest.distance <= maximumMatchDistance {
                matchedFaceIDsByPerson[nearest.personID, default: []].append(face.faceID)
            } else {
                unmatchedFaces.append(face)
            }
        }

        var clusters: [(faceIDs: [FaceID], vectorSum: [Double])] = []
        for face in unmatchedFaces {
            let nearestIndex = clusters.indices
                .compactMap { index -> (index: Int, distance: Double)? in
                    guard let mean = Self.normalized(clusters[index].vectorSum),
                          let distance = Self.distance(face.vector, mean) else {
                        return nil
                    }
                    return (index: index, distance: distance)
                }
                .min { $0.distance < $1.distance }
            if let nearestIndex, nearestIndex.distance <= maximumClusterDistance {
                clusters[nearestIndex.index].faceIDs.append(face.faceID)
                clusters[nearestIndex.index].vectorSum = zip(clusters[nearestIndex.index].vectorSum, face.vector).map(+)
            } else {
                clusters.append((faceIDs: [face.faceID], vectorSum: face.vector))
            }
        }

        let matches = matchedFaceIDsByPerson
            .map { FaceMatchSuggestion(personID: $0.key, faceIDs: $0.value) }
            .sorted { lhs, rhs in
                if lhs.faceIDs.count != rhs.faceIDs.count {
                    return lhs.faceIDs.count > rhs.faceIDs.count
                }
                return lhs.personID < rhs.personID
            }
        let clusterSuggestions = clusters
            .filter { $0.faceIDs.count >= minimumClusterFaceCount }
            .map { FaceClusterSuggestion(faceIDs: $0.faceIDs) }
            .sorted { lhs, rhs in
                if lhs.faceIDs.count != rhs.faceIDs.count {
                    return lhs.faceIDs.count > rhs.faceIDs.count
                }
                return (lhs.faceIDs.first?.assetID.rawValue ?? "") < (rhs.faceIDs.first?.assetID.rawValue ?? "")
            }
        return FaceSuggestions(matches: matches, clusters: clusterSuggestions)
    }

    private static func normalized(_ vector: [Double]) -> [Double]? {
        guard !vector.isEmpty else { return nil }
        let magnitude = vector.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard magnitude > 0 else { return nil }
        return vector.map { $0 / magnitude }
    }

    private static func centroid(of vectors: [[Double]]) -> [Double]? {
        let normalizedVectors = vectors.compactMap(normalized)
        guard let dimension = normalizedVectors.first?.count else { return nil }
        let matching = normalizedVectors.filter { $0.count == dimension }
        var sum = [Double](repeating: 0, count: dimension)
        for vector in matching {
            for index in vector.indices {
                sum[index] += vector[index]
            }
        }
        return normalized(sum)
    }

    private static func distance(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        return zip(lhs, rhs)
            .map { first, second in
                let delta = first - second
                return delta * delta
            }
            .reduce(0, +)
            .squareRoot()
    }
}
