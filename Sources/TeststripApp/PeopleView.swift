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
                Text(presentation.statusTitle)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text(presentation.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(presentation.signalRows) { row in
                    Button {
                        selectPeopleSignal(row)
                    } label: {
                        peopleSignalCard(row)
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.isActionEnabled)
                    .help(row.isActionEnabled ? "Show \(row.title.lowercased())" : row.detail)
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
            Text("PEOPLE GROUPS")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(avatarGradient(seed: "pending-face-groups", colors: [.orange, .brown]))
                    .frame(width: 74, height: 74)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12))
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Naming is not built yet")
                        .font(.headline.weight(.semibold))
                    Text("Unnamed face review is live from local face signals; clustering, naming, and merge decisions stay disabled until identity grouping ships.")
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

    private func peopleSignalCard(_ row: PeopleSignalRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .background(Color.orange.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.countText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
            if row.isActionEnabled {
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.07))
        }
    }

    private func selectPeopleSignal(_ row: PeopleSignalRow) {
        guard let kind = row.filterKind else { return }
        do {
            try model.selectPeopleSignal(kind)
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

struct PeopleFaceActionRow: Equatable, Identifiable {
    var id: String { title }
    var title: String
    var isEnabled = false
    var placeholder = LiveMockupPlaceholders.peopleFaceActions
}
