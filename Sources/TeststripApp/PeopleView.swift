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
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.07))
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
                    Text("Named people are not built yet")
                        .font(.headline.weight(.semibold))
                    Text("This route is ready for face clustering and naming, but it only shows local face-signal coverage today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(["Name clusters", "Merge duplicates", "Dismiss false positives"], id: \.self) { title in
                            Button(title) {}
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(true)
                                .liveMockupPlaceholder(.peopleFaceActions)
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
    var photosWithFaceQualitySignals: Int

    init(totalAssetCount: Int, evaluationSummaries: [CatalogEvaluationKindSummary]) {
        self.totalAssetCount = totalAssetCount
        let faceCountSignals = evaluationSummaries.first { $0.kind == .faceCount }?.assetCount ?? 0
        let faceQualitySignals = evaluationSummaries.first { $0.kind == .faceQuality }?.assetCount ?? 0
        self.photosWithFaceSignals = max(faceCountSignals, faceQualitySignals)
        self.photosWithFaceQualitySignals = faceQualitySignals
    }

    var headerSummary: String {
        if photosWithFaceSignals > 0 {
            return "0 people · \(photosWithFaceSignals) photos with face signals"
        }
        return "0 people · \(totalAssetCount) photos"
    }

    var statusTitle: String {
        photosWithFaceSignals > 0 ? "TESTSTRIP · FACE GROUPING NOT BUILT" : "TESTSTRIP · NO FACE SIGNALS YET"
    }

    var statusDetail: String {
        if photosWithFaceSignals > 0 {
            return "\(photosWithFaceSignals) photos have face signals. Naming starts after clustering ships."
        }
        return "Run evaluation on catalog photos to populate local face signals."
    }

    var signalRows: [PeopleSignalRow] {
        [
            PeopleSignalRow(
                id: "face-count",
                title: "Photos with faces",
                detail: "Assets with local face signals",
                countText: "\(photosWithFaceSignals)",
                systemImage: "person.crop.rectangle.stack"
            ),
            PeopleSignalRow(
                id: "face-quality",
                title: "Face quality reads",
                detail: "Assets with face-quality measurements",
                countText: "\(photosWithFaceQualitySignals)",
                systemImage: "face.smiling"
            )
        ]
    }
}

struct PeopleSignalRow: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var countText: String
    var systemImage: String
}
