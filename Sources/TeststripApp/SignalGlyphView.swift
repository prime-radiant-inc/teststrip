import SwiftUI

/// One micro signal glyph: an 11pt donut ring (arc sweep = score) with the
/// measure's word beside it. The reads card's glyph line is built from these
/// and is this view's only consumer. SP-B's per-face report cards do NOT
/// reuse it — `FaceSignalChipView` is a sibling with its own 17pt
/// icon-in-donut geometry, because a 112pt face tile has room for four icons
/// but not four words. Changing this view does not change the face tiles.
struct SignalGlyphView: View {
    let entry: CullReadsCardPresentation.GlyphEntry

    private static let donutSize: CGFloat = 11
    private static let ringWidth: CGFloat = 2.2
    private static let fillColor = Color(red: 0.35, green: 0.78, blue: 0.78)

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.18), lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: max(0, min(1, entry.score)))
                    .stroke(Self.fillColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Self.donutSize, height: Self.donutSize)
            Text(entry.word)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(entry.accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
    }
}
