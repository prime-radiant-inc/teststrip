import Foundation

public struct PersonCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let similarityPercent: Int?

    public init(id: String, name: String, similarityPercent: Int?) {
        self.id = id
        self.name = name
        self.similarityPercent = similarityPercent
    }
}

/// Ranks people for the naming autocompleter: by face-similarity to a target
/// face when one is given, else by most-recently-used then alphabetical.
public enum PersonCandidateRanker {
    public static func rank(
        targetEmbedding: [Double]?,
        centroidsByPerson: [String: [Double]],
        namesByID: [String: String],
        recentPersonIDs: [String]
    ) -> [PersonCandidate] {
        let normalizedTarget = targetEmbedding.flatMap(FaceSuggestionBuilder.normalized)

        var scored: [(candidate: PersonCandidate, distance: Double)] = []
        var tailIDs: [String] = []
        for (id, name) in namesByID {
            if let normalizedTarget, let centroid = centroidsByPerson[id],
               let distance = FaceSuggestionBuilder.distance(normalizedTarget, centroid) {
                scored.append((PersonCandidate(id: id, name: name, similarityPercent: FaceSimilarity.percent(distance: distance)), distance))
            } else {
                tailIDs.append(id)
            }
        }

        let ranked = scored.sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.candidate.name != rhs.candidate.name { return lhs.candidate.name < rhs.candidate.name }
            return lhs.candidate.id < rhs.candidate.id
        }.map(\.candidate)

        let recencyIndex = Dictionary(uniqueKeysWithValues: recentPersonIDs.enumerated().map { ($1, $0) })
        let tail = tailIDs.sorted { lhs, rhs in
            let lr = recencyIndex[lhs], rr = recencyIndex[rhs]
            if lr != rr {
                // Present in the recent list sorts before absent; earlier index = more recent = first.
                switch (lr, rr) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            let ln = namesByID[lhs] ?? "", rn = namesByID[rhs] ?? ""
            if ln != rn { return ln < rn }
            return lhs < rhs
        }.map { PersonCandidate(id: $0, name: namesByID[$0] ?? "", similarityPercent: nil) }

        return ranked + tail
    }
}
