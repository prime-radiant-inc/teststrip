import Foundation

public struct AutopilotPlanInput {
    public var assets: [Asset]
    public var signalsByAssetID: [AssetID: [EvaluationSignal]]
    public var keywordCandidatesByAssetID: [AssetID: [String]]

    public init(
        assets: [Asset],
        signalsByAssetID: [AssetID: [EvaluationSignal]],
        keywordCandidatesByAssetID: [AssetID: [String]]
    ) {
        self.assets = assets
        self.signalsByAssetID = signalsByAssetID
        self.keywordCandidatesByAssetID = keywordCandidatesByAssetID
    }
}

/// Pure planner that turns a scope's assets, their evaluation signals, and
/// stack groupings into provisional pick/reject/keyword proposals. It is
/// deterministic and honest: it proposes a keep/cut only inside a detected
/// multi-frame stack whose members carry rankable signals, and keyword
/// proposals only from candidates the caller already extracted. It never writes
/// metadata; callers persist the returned proposals as `pending`.
public struct AutopilotProposalPlanner {
    public var stackBuilder: AssetStackBuilder

    public init(stackBuilder: AssetStackBuilder) {
        self.stackBuilder = stackBuilder
    }

    public func proposals(for input: AutopilotPlanInput, runID: AutopilotRunID, now: Date) -> [AutopilotProposal] {
        var proposals: [AutopilotProposal] = []

        let stacks = stackBuilder.stacks(from: input.assets, visualSimilarityVectorsByAssetID: [:])
        for stack in stacks where stack.assetIDs.count > 1 {
            proposals.append(contentsOf: cullProposals(for: stack, input: input, runID: runID, now: now))
        }

        for asset in input.assets {
            guard let candidates = input.keywordCandidatesByAssetID[asset.id] else { continue }
            var seen = Set<String>()
            for keyword in candidates {
                guard seen.insert(keyword).inserted else { continue }
                proposals.append(makeProposal(
                    runID: runID,
                    assetID: asset.id,
                    kind: .keyword,
                    keyword: keyword,
                    rationale: "Detected \(keyword)",
                    confidence: 0.6,
                    now: now
                ))
            }
        }

        return proposals
    }

    private func cullProposals(
        for stack: AssetStack,
        input: AutopilotPlanInput,
        runID: AutopilotRunID,
        now: Date
    ) -> [AutopilotProposal] {
        let ranked = stack.assetIDs.compactMap { assetID -> (assetID: AssetID, score: Double)? in
            guard let score = CullingQualityScore.qualityScore(for: input.signalsByAssetID[assetID] ?? []) else {
                return nil
            }
            return (assetID: assetID, score: score)
        }
        // Nothing to rank honestly if no member carries a rankable signal.
        guard !ranked.isEmpty else { return [] }

        let isRawByAssetID = Dictionary(
            input.assets.map { ($0.id, $0.isRawOriginal) },
            uniquingKeysWith: { first, _ in first }
        )
        let sorted = ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            // Equal quality (e.g. a RAW+JPEG pair of the same shot): keep the RAW.
            let lhsRaw = isRawByAssetID[lhs.assetID] ?? false
            let rhsRaw = isRawByAssetID[rhs.assetID] ?? false
            if lhsRaw != rhsRaw { return lhsRaw }
            return lhs.assetID.rawValue < rhs.assetID.rawValue
        }
        guard let winner = sorted.first else { return [] }

        let count = stack.assetIDs.count
        let margin = winningMargin(sorted: sorted)
        var result: [AutopilotProposal] = [makeProposal(
            runID: runID,
            assetID: winner.assetID,
            kind: .pick,
            keyword: nil,
            rationale: "Sharpest frame in its burst of \(count)",
            confidence: margin,
            now: now
        )]
        for candidate in sorted.dropFirst() {
            result.append(makeProposal(
                runID: runID,
                assetID: candidate.assetID,
                kind: .reject,
                keyword: nil,
                rationale: "Weaker frame in a burst of \(count)",
                confidence: margin,
                now: now
            ))
        }
        return result
    }

    private func winningMargin(sorted: [(assetID: AssetID, score: Double)]) -> Double {
        guard let winner = sorted.first else { return 0 }
        guard sorted.count > 1 else { return 1 }
        let runnerUp = sorted[1]
        guard winner.score > 0 else { return 0 }
        return min(max((winner.score - runnerUp.score) / winner.score, 0), 1)
    }

    private func makeProposal(
        runID: AutopilotRunID,
        assetID: AssetID,
        kind: AutopilotProposalKind,
        keyword: String?,
        rationale: String,
        confidence: Double,
        now: Date
    ) -> AutopilotProposal {
        AutopilotProposal(
            id: AutopilotProposalID(rawValue: "\(runID.rawValue)-\(assetID.rawValue)-\(kind.rawValue)-\(keyword ?? "")"),
            runID: runID,
            assetID: assetID,
            kind: kind,
            keyword: keyword,
            rationale: rationale,
            confidence: confidence,
            status: .pending,
            createdAt: now,
            updatedAt: now
        )
    }
}
