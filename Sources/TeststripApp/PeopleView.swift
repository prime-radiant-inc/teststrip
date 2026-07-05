import SwiftUI
import TeststripCore

struct PeopleView: View {
    var model: AppModel

    private var presentation: PeoplePresentation {
        PeoplePresentation(
            totalAssetCount: model.totalAssetCount,
            evaluationSummaries: model.catalogEvaluationKindSummaries
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                recognitionStatusPanel
                pendingPeoplePanel
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.08))
        .liveMockupPlaceholder(.peopleSidebar)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("People")
                .font(.title2.weight(.semibold))
            Spacer()
            Text(presentation.headerSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var recognitionStatusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text(presentation.reviewStripTitle)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                Text("0 matched")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(presentation.reviewStripDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if presentation.reviewCards.isEmpty {
                Text(presentation.namedPeopleEmptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(presentation.reviewCards) { card in
                        Button {
                            selectPeopleReviewCard(card)
                        } label: {
                            peopleReviewCard(card)
                        }
                        .buttonStyle(.plain)
                        .disabled(!card.isActionEnabled)
                        .help(card.isActionEnabled ? card.suggestedActionTitle : "Face naming is not built yet")
                    }
                }
            }
        }
        .padding(15)
        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.18))
        }
    }

    private var pendingPeoplePanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(presentation.namedPeopleTitle)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(avatarGradient(seed: "pending-face-groups", colors: [.orange, .brown]))
                    .frame(width: 58, height: 58)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12))
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Named people are not built yet")
                        .font(.headline.weight(.semibold))
                    Text(presentation.namedPeopleEmptyText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(presentation.faceActionRows) { row in
                            Button(row.title) {}
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!row.isEnabled)
                                .liveMockupPlaceholder(row.placeholder)
                        }
                    }
                }
            }
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.07))
            }
        }
    }

    private func peopleReviewCard(_ card: PeopleReviewCard) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarGradient(seed: card.id, colors: card.gradientColors))
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(card.countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(card.suggestedActionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.isActionEnabled ? .primary : .secondary)
                    if !card.isNamingEnabled {
                        Image(systemName: "lock")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .liveMockupPlaceholder(.peopleFaceActions)
                    }
                }
                Text(card.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if card.isActionEnabled {
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.07))
        }
    }

    private func selectPeopleReviewCard(_ card: PeopleReviewCard) {
        guard let target = card.target else { return }
        do {
            try model.selectSidebarTarget(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func avatarGradient(seed: String, colors: [Color]) -> LinearGradient {
        let seedValue = seed.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        let angle = Angle(degrees: Double(seedValue % 160 + 20))
        return LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.2, y: 0.1), endPoint: UnitPoint(x: cos(angle.radians), y: sin(angle.radians)))
    }
}

struct PeoplePresentation: Equatable {
    var totalAssetCount: Int
    var photosWithFaceSignals: Int
    var photosWithDetectedFaces: Int
    var photosWithFaceQualitySignals: Int
    private var faceSignalKind: EvaluationKind?

    init(totalAssetCount: Int, evaluationSummaries: [CatalogEvaluationKindSummary]) {
        self.totalAssetCount = totalAssetCount
        let faceCountSignals = evaluationSummaries.first { $0.kind == .faceCount }?.assetCount ?? 0
        let faceQualitySignals = evaluationSummaries.first { $0.kind == .faceQuality }?.assetCount ?? 0
        self.photosWithFaceSignals = max(faceCountSignals, faceQualitySignals)
        self.photosWithDetectedFaces = faceCountSignals > 0 ? faceCountSignals : faceQualitySignals
        self.photosWithFaceQualitySignals = faceQualitySignals
        self.faceSignalKind = faceCountSignals > 0 ? .faceCount : (faceQualitySignals > 0 ? .faceQuality : nil)
    }

    var headerSummary: String {
        if photosWithFaceSignals > 0 {
            return "0 people · \(photosWithFaceSignals) photos with face signals"
        }
        return "0 people · \(totalAssetCount) photos"
    }

    var statusTitle: String {
        photosWithFaceSignals > 0 ? "TESTSTRIP · FACE REVIEW QUEUE" : "TESTSTRIP · NO FACE REVIEW SIGNALS"
    }

    var statusDetail: String {
        if photosWithFaceSignals > 0 {
            return "Review \(photosWithFaceSignals) photos with unnamed face signals. Naming and clustering are still disabled."
        }
        return "Run evaluation on catalog photos to populate local face review queues."
    }

    var reviewStripTitle: String {
        guard photosWithFaceSignals > 0 else {
            return "TESTSTRIP · NO FACE REVIEW SIGNALS"
        }
        return "TESTSTRIP · \(Self.photoCountDescription(photosWithDetectedFaces).uppercased()) NEED FACE REVIEW"
    }

    var reviewStripDetail: String {
        guard photosWithFaceSignals > 0 else {
            return "Run evaluation on catalog photos to populate local face review queues."
        }
        if photosWithFaceQualitySignals > 0 {
            return "\(Self.photoCountDescription(photosWithFaceQualitySignals)) have face-quality signals; named people are not built yet."
        }
        return "\(Self.photoCountDescription(photosWithDetectedFaces)) have local face detections; named people are not built yet."
    }

    var reviewCards: [PeopleReviewCard] {
        var cards: [PeopleReviewCard] = []
        if photosWithDetectedFaces > 0, let faceSignalKind {
            cards.append(PeopleReviewCard(
                id: "unnamed-faces",
                title: "Unnamed faces",
                countText: Self.photoCountDescription(photosWithDetectedFaces),
                suggestedActionTitle: "Review faces",
                filterKind: faceSignalKind,
                target: faceSignalKind == .faceCount ? .reviewQueue(.facesFound) : .evaluationKind(faceSignalKind),
                gradientColors: [.orange, .brown]
            ))
        }
        if photosWithFaceQualitySignals > 0 {
            cards.append(PeopleReviewCard(
                id: "face-quality",
                title: "Face quality checks",
                countText: Self.photoCountDescription(photosWithFaceQualitySignals),
                suggestedActionTitle: "Review quality",
                filterKind: .faceQuality,
                target: .evaluationKind(.faceQuality),
                gradientColors: [.orange, .yellow]
            ))
        }
        return cards
    }

    var namedPeopleTitle: String {
        "ALL PEOPLE"
    }

    var namedPeopleEmptyText: String {
        if photosWithFaceSignals > 0 {
            return "Named people will appear here after face clustering and confirmation ship."
        }
        return "Run evaluation to find faces before naming people."
    }

    var signalRows: [PeopleSignalRow] {
        [
            PeopleSignalRow(
                id: "face-count",
                title: "Unnamed faces",
                detail: "Review assets with local face detections",
                countText: "\(photosWithDetectedFaces)",
                systemImage: "person.crop.rectangle.stack",
                filterKind: faceSignalKind
            ),
            PeopleSignalRow(
                id: "face-quality",
                title: "Face quality review",
                detail: "Review assets with face-quality measurements",
                countText: "\(photosWithFaceQualitySignals)",
                systemImage: "face.smiling",
                filterKind: photosWithFaceQualitySignals > 0 ? .faceQuality : nil
            )
        ]
    }

    var faceActionRows: [PeopleFaceActionRow] {
        [
            PeopleFaceActionRow(title: "Name clusters"),
            PeopleFaceActionRow(title: "Merge duplicates"),
            PeopleFaceActionRow(title: "Dismiss false positives")
        ]
    }

    private static func photoCountDescription(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }
}

struct PeopleSignalRow: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var countText: String
    var systemImage: String
    var filterKind: EvaluationKind?

    var isActionEnabled: Bool {
        filterKind != nil
    }
}

struct PeopleReviewCard: Equatable, Identifiable {
    var id: String
    var title: String
    var countText: String
    var suggestedActionTitle: String
    var filterKind: EvaluationKind?
    var target: SidebarRowTarget?
    var isNamingEnabled = false
    var gradientColors: [Color]

    var isActionEnabled: Bool {
        target != nil
    }
}

struct PeopleFaceActionRow: Equatable, Identifiable {
    var id: String { title }
    var title: String
    var isEnabled = false
    var placeholder = LiveMockupPlaceholders.peopleFaceActions
}
