import XCTest
@testable import TeststripCore

final class AutopilotProposalPlannerTests: XCTestCase {
    func testProposesKeepForStackWinnerAndCutForAlternates() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = asset(id: "lead", capturedAt: capturedAt)
        let alternate = asset(id: "alt", capturedAt: capturedAt.addingTimeInterval(1))
        let planner = AutopilotProposalPlanner(stackBuilder: AssetStackBuilder(maximumCaptureGap: 2))
        let input = AutopilotPlanInput(
            assets: [lead, alternate],
            signalsByAssetID: [
                lead.id: [signal(lead.id, .focus, 0.30)],
                alternate.id: [signal(alternate.id, .focus, 0.95)]
            ],
            keywordCandidatesByAssetID: [:]
        )

        let proposals = planner.proposals(for: input, runID: AutopilotRunID(rawValue: "r"), now: capturedAt)

        XCTAssertEqual(proposals.first { $0.assetID == alternate.id }?.kind, .pick)
        XCTAssertEqual(proposals.first { $0.assetID == lead.id }?.kind, .reject)
        XCTAssertTrue(proposals.allSatisfy { $0.status == .pending && $0.runID.rawValue == "r" })
    }

    func testProposesNoCullForSingletonFrames() {
        let lead = asset(id: "solo", capturedAt: Date(timeIntervalSince1970: 100))
        let planner = AutopilotProposalPlanner(stackBuilder: AssetStackBuilder(maximumCaptureGap: 2))
        let input = AutopilotPlanInput(
            assets: [lead],
            signalsByAssetID: [lead.id: [signal(lead.id, .focus, 0.9)]],
            keywordCandidatesByAssetID: [:]
        )

        let proposals = planner.proposals(for: input, runID: AutopilotRunID(rawValue: "r"), now: Date())

        XCTAssertTrue(proposals.filter { $0.kind == .pick || $0.kind == .reject }.isEmpty)
    }

    func testProposesKeywordsFromCandidates() {
        let lead = asset(id: "kw", capturedAt: Date(timeIntervalSince1970: 100))
        let planner = AutopilotProposalPlanner(stackBuilder: AssetStackBuilder(maximumCaptureGap: 2))
        let input = AutopilotPlanInput(
            assets: [lead],
            signalsByAssetID: [:],
            keywordCandidatesByAssetID: [lead.id: ["dog", "beach"]]
        )

        let proposals = planner.proposals(for: input, runID: AutopilotRunID(rawValue: "r"), now: Date())

        XCTAssertEqual(Set(proposals.filter { $0.kind == .keyword }.compactMap(\.keyword)), ["dog", "beach"])
    }

    private func asset(id: String, capturedAt: Date) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: capturedAt),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000, pixelHeight: 4000, capturedAt: capturedAt,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }

    private func signal(_ assetID: AssetID, _ kind: EvaluationKind, _ score: Double) -> EvaluationSignal {
        EvaluationSignal(
            assetID: assetID, kind: kind, value: .score(score), confidence: 0.9,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "1", settingsHash: "default")
        )
    }
}
