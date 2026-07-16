import Foundation
import TeststripCore

/// Machine-derived stack labels for culling surfaces: file range, frame
/// count, start time. Stacks are auto-grouped — labels must never imply
/// curated names.
struct CullStackLabelPresentation {
    static func label(for assets: [Asset]) -> String {
        guard let first = assets.first else { return "" }
        if assets.count == 1 { return standaloneLabel(for: first) }
        var segments = [fileRange(for: assets), "\(assets.count)"]
        if let time = timeText(for: first) { segments.append(time) }
        return segments.joined(separator: " · ")
    }

    static func standaloneLabel(for asset: Asset) -> String {
        var segments = [stem(of: asset)]
        if let time = timeText(for: asset) { segments.append(time) }
        return segments.joined(separator: " · ")
    }

    private static func stem(of asset: Asset) -> String {
        asset.originalURL.deletingPathExtension().lastPathComponent
    }

    private static func timeText(for asset: Asset) -> String? {
        asset.technicalMetadata?.capturedAt?.formatted(date: .omitted, time: .shortened)
    }

    private static func fileRange(for assets: [Asset]) -> String {
        let stems = assets.map(stem(of:))
        guard let first = stems.first, let last = stems.last else { return "" }
        // Collapse "IMG_0412"…"IMG_0417" to "IMG_0412–0417" when both share
        // a prefix and end in digits; otherwise fall back to "first…last".
        let firstDigits = trailingDigits(of: first)
        let lastDigits = trailingDigits(of: last)
        let firstPrefix = String(first.dropLast(firstDigits.count))
        let lastPrefix = String(last.dropLast(lastDigits.count))
        if !firstDigits.isEmpty, !lastDigits.isEmpty, firstPrefix == lastPrefix {
            return "\(first)–\(lastDigits)"
        }
        return "\(first)…\(last)"
    }

    private static func trailingDigits(of stem: String) -> String {
        String(stem.reversed().prefix(while: \.isNumber).reversed())
    }
}
