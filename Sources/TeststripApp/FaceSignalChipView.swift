import SwiftUI

/// One per-face signal chip: a 17pt donut ring whose sweep is the score, with
/// a stylized monochrome icon inside naming the signal. A sibling of
/// `SignalGlyphView` (the reads card's 11pt word-beside-donut glyph), not a
/// variant of it — the reads card shows whole-photo measures with room for a
/// word, a face tile shows four measures in 112pt with room only for icons.
struct FaceSignalChipView: View {
    let entry: FaceReportChipPresentation.Entry

    private static let donutSize: CGFloat = 17
    private static let ringWidth: CGFloat = 2.4
    private static let fillColor = Color(red: 0.35, green: 0.78, blue: 0.78)

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: Self.ringWidth)
            // An unscored signal leaves the ring empty: no sweep at all, so
            // "not measured" can never look like "measured zero" or a clean
            // full ring.
            if let score = entry.score {
                Circle()
                    .trim(from: 0, to: max(0, min(1, score)))
                    .stroke(Self.fillColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: entry.signal.symbolName)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.donutSize, height: Self.donutSize)
        .help(entry.accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
    }
}
