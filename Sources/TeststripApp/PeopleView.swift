import SwiftUI

struct PeopleView: View {
    var model: AppModel

    private let unnamedFaces = [
        PeoplePlaceholderFace(id: "face-1", photoCount: 18, suggestion: "Confirm match"),
        PeoplePlaceholderFace(id: "face-2", photoCount: 11, suggestion: "Name"),
        PeoplePlaceholderFace(id: "face-3", photoCount: 7, suggestion: "Merge")
    ]

    private let people = [
        PeoplePlaceholderPerson(id: "person-1", name: "Avery", photoCount: 342, colors: [.orange, .pink]),
        PeoplePlaceholderPerson(id: "person-2", name: "Morgan", photoCount: 218, colors: [.blue, .purple]),
        PeoplePlaceholderPerson(id: "person-3", name: "Sam", photoCount: 176, colors: [.green, .mint]),
        PeoplePlaceholderPerson(id: "person-4", name: "Jordan", photoCount: 144, colors: [.yellow, .orange]),
        PeoplePlaceholderPerson(id: "person-5", name: "Taylor", photoCount: 98, colors: [.teal, .cyan]),
        PeoplePlaceholderPerson(id: "person-6", name: "Riley", photoCount: 75, colors: [.indigo, .blue])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                needsNamingPanel
                peopleGrid
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
            Text("\(people.count) people · \(model.totalAssetCount) photos")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var needsNamingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text("TESTSTRIP · \(unnamedFaces.count) FACES NEED A NAME")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
                Text("· 44 others matched automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(unnamedFaces) { face in
                    HStack(spacing: 12) {
                        faceAvatar(face.id)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(face.photoCount) photos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Button(face.suggestion) {}
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(true)
                                    .liveMockupPlaceholder(.peopleFaceActions)
                                Button {} label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(true)
                                .liveMockupPlaceholder(.peopleFaceActions)
                            }
                        }
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

    private var peopleGrid: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("ALL PEOPLE")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 16)], spacing: 18) {
                ForEach(people) { person in
                    VStack(spacing: 9) {
                        personAvatar(person)
                            .aspectRatio(1, contentMode: .fit)
                        VStack(spacing: 2) {
                            Text(person.name)
                                .font(.caption.weight(.semibold))
                            Text("\(person.photoCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func faceAvatar(_ seed: String) -> some View {
        Circle()
            .fill(avatarGradient(seed: seed, colors: [.orange, .brown]))
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func personAvatar(_ person: PeoplePlaceholderPerson) -> some View {
        Circle()
            .fill(avatarGradient(seed: person.id, colors: person.colors))
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private func avatarGradient(seed: String, colors: [Color]) -> LinearGradient {
        let seedValue = seed.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        let angle = Angle(degrees: Double(seedValue % 160 + 20))
        return LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.2, y: 0.1), endPoint: UnitPoint(x: cos(angle.radians), y: sin(angle.radians)))
    }
}

private struct PeoplePlaceholderFace: Identifiable {
    var id: String
    var photoCount: Int
    var suggestion: String
}

private struct PeoplePlaceholderPerson: Identifiable {
    var id: String
    var name: String
    var photoCount: Int
    var colors: [Color]
}
