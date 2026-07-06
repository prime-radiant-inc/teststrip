import Foundation
import TeststripCore

public struct LibrarySearchIntent: Equatable, Sendable {
    public var residualText: String?
    public var predicates: [SetQuery.Predicate]
    public var chips: [String]
    public var nameParts: [String]

    public init(
        residualText: String? = nil,
        predicates: [SetQuery.Predicate] = [],
        chips: [String] = [],
        nameParts: [String] = []
    ) {
        self.residualText = residualText
        self.predicates = predicates
        self.chips = chips
        self.nameParts = nameParts
    }

    public static func parse(_ text: String) -> LibrarySearchIntent {
        let normalized = Self.normalizedWhitespace(text)
        guard !normalized.isEmpty else {
            return LibrarySearchIntent()
        }

        let tokens = Self.searchTokens(from: text)
        var residualTokens: [String] = []
        var predicates: [SetQuery.Predicate] = []
        var chips: [String] = []
        var nameParts: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let normalizedToken = Self.normalizedToken(token)

            if let field = Self.fieldPredicates(from: token) {
                for predicate in field.predicates {
                    Self.append(predicate, to: &predicates)
                }
                for chip in field.chips {
                    Self.append(chip, to: &chips)
                }
                for namePart in field.nameParts {
                    Self.append(namePart, to: &nameParts)
                }
                index += 1
                continue
            }

            if let flag = Self.flagPredicate(for: normalizedToken) {
                Self.removeFlagPredicates(from: &predicates)
                Self.append(.flag(flag.value), to: &predicates)
                Self.append(flag.chip, to: &chips)
                Self.append(flag.namePart, to: &nameParts)
                index += 1
                continue
            }

            if let rating = Self.ratingPredicate(in: tokens, at: index) {
                Self.removeRatingPredicates(from: &predicates)
                Self.append(.ratingAtLeast(rating.value), to: &predicates)
                Self.append("Rating >= \(rating.value)", to: &chips)
                Self.append("\(rating.value)+ Stars", to: &nameParts)
                index += rating.consumedTokenCount
                continue
            }

            if let phrase = Self.phrasePredicate(in: tokens, at: index) {
                Self.append(phrase.predicate, to: &predicates)
                Self.append(phrase.chip, to: &chips)
                Self.append(phrase.namePart, to: &nameParts)
                index += phrase.consumedTokenCount
                continue
            }

            residualTokens.append(token)
            index += 1
        }

        let residualText = Self.normalizedWhitespace(residualTokens.joined(separator: " "))
        return LibrarySearchIntent(
            residualText: residualText.isEmpty ? nil : residualText,
            predicates: predicates,
            chips: chips,
            nameParts: nameParts
        )
    }

    private struct FieldPredicates {
        var predicates: [SetQuery.Predicate]
        var chips: [String]
        var nameParts: [String]
    }

    private static func fieldPredicates(from token: String) -> FieldPredicates? {
        guard let fieldToken = fieldToken(from: token) else {
            return nil
        }
        let field = normalizedToken(fieldToken.field)
        let value = fieldToken.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        switch field {
        case "camera":
            return singleFieldPredicate(.camera(value), chip: "Camera: \(value)", namePart: value)
        case "lens":
            return singleFieldPredicate(.lens(value), chip: "Lens: \(value)", namePart: value)
        case "keyword", "tag":
            return singleFieldPredicate(.keyword(value), chip: "Keyword: \(value)", namePart: value)
        case "folder", "path":
            let title = URL(fileURLWithPath: value).lastPathComponent
            return singleFieldPredicate(.folderPrefix(value), chip: "Folder: \(title)", namePart: title)
        case "color", "colour", "label":
            guard let label = colorLabel(from: value) else { return nil }
            let title = "\(label.rawValue.capitalized) Label"
            return singleFieldPredicate(.colorLabel(label), chip: title, namePart: title)
        case "iso":
            guard let iso = positiveInteger(from: value) else { return nil }
            return singleFieldPredicate(.isoAtLeast(iso), chip: "ISO >= \(iso)", namePart: "ISO \(iso)+")
        case "rating", "rated", "star", "stars":
            guard let rating = ratingValue(from: normalizedToken(value)) else { return nil }
            return singleFieldPredicate(.ratingAtLeast(rating), chip: "Rating >= \(rating)", namePart: "\(rating)+ Stars")
        case "from", "after", "since":
            guard let date = captureDate(from: value) else { return nil }
            return singleFieldPredicate(.capturedAtOrAfter(date), chip: "From \(value)", namePart: "From \(value)")
        case "before", "until":
            guard let date = captureDate(from: value) else { return nil }
            return singleFieldPredicate(.capturedBefore(date), chip: "Before \(value)", namePart: "Before \(value)")
        case "date", "day", "captured":
            guard let start = captureDate(from: value),
                  let end = dayAfter(start) else {
                return nil
            }
            return FieldPredicates(
                predicates: [.capturedAtOrAfter(start), .capturedBefore(end)],
                chips: ["Date: \(value)"],
                nameParts: [value]
            )
        case "source", "availability":
            guard let availability = sourceAvailability(from: value) else { return nil }
            let title = availability.rawValue.capitalized
            return singleFieldPredicate(.availability(availability), chip: "Source: \(title)", namePart: title)
        case "signal", "evaluation", "kind":
            guard let kind = evaluationKind(from: value) else { return nil }
            let title = kind.displayName
            return singleFieldPredicate(.evaluationKind(kind), chip: "Signal: \(title)", namePart: title)
        case "xmp":
            guard let xmp = xmpPredicate(from: value) else { return nil }
            return singleFieldPredicate(xmp.predicate, chip: xmp.title, namePart: xmp.title)
        case "session", "worksession":
            return singleFieldPredicate(.workSession(value), chip: "Session: \(value)", namePart: "Session \(value)")
        case "import", "importbatch", "batch":
            return singleFieldPredicate(.importBatch(value), chip: "Import: \(value)", namePart: "Import \(value)")
        default:
            return nil
        }
    }

    private static func singleFieldPredicate(
        _ predicate: SetQuery.Predicate,
        chip: String,
        namePart: String
    ) -> FieldPredicates {
        FieldPredicates(predicates: [predicate], chips: [chip], nameParts: [namePart])
    }

    private static func fieldToken(from token: String) -> (field: String, value: String)? {
        for separator in [":", ">=", "="] {
            guard let range = token.range(of: separator) else { continue }
            let field = String(token[..<range.lowerBound])
            let value = String(token[range.upperBound...])
            guard !field.isEmpty, !value.isEmpty else { return nil }
            return (field, value)
        }
        return nil
    }

    private static func colorLabel(from value: String) -> ColorLabel? {
        let normalized = compactIdentifier(value)
        return ColorLabel.allCases.first { compactIdentifier($0.rawValue) == normalized }
    }

    private static func sourceAvailability(from value: String) -> SourceAvailability? {
        let normalized = compactIdentifier(value)
        return [SourceAvailability.online, .offline, .missing, .moved, .stale].first {
            compactIdentifier($0.rawValue) == normalized
        }
    }

    private static func evaluationKind(from value: String) -> EvaluationKind? {
        let normalized = compactIdentifier(value)
        return [
            EvaluationKind.focus,
            .motionBlur,
            .exposure,
            .aesthetics,
            .framing,
            .object,
            .faceCount,
            .faceQuality,
            .ocrText,
            .colorPalette,
            .novelty,
            .visualSimilarity
        ].first { compactIdentifier($0.rawValue) == normalized }
    }

    private static func xmpPredicate(from value: String) -> (predicate: SetQuery.Predicate, title: String)? {
        switch compactIdentifier(value) {
        case "pending":
            return (.metadataSyncPending, "XMP Pending")
        case "conflict", "conflicts":
            return (.metadataSyncConflict, "XMP Conflicts")
        default:
            return nil
        }
    }

    private static func positiveInteger(from value: String) -> Int? {
        guard let integer = Int(value), integer > 0 else { return nil }
        return integer
    }

    private static func captureDate(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == parts[0],
              components.month == parts[1],
              components.day == parts[2] else {
            return nil
        }
        return date
    }

    private static func dayAfter(_ date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(byAdding: .day, value: 1, to: date)
    }

    private static func compactIdentifier(_ value: String) -> String {
        normalizedToken(value)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func flagPredicate(for token: String) -> (value: PickFlag, chip: String, namePart: String)? {
        switch token {
        case "pick", "picks", "picked", "keeper", "keepers", "select", "selects", "selected":
            return (.pick, "Pick", "Pick")
        case "reject", "rejects", "rejected", "rejecting":
            return (.reject, "Reject", "Reject")
        default:
            return nil
        }
    }

    private static func ratingPredicate(in tokens: [String], at index: Int) -> (value: Int, consumedTokenCount: Int)? {
        let token = normalizedToken(tokens[index])
        if let compact = compactRatingValue(from: token) {
            return (compact, 1)
        }

        if let value = ratingValue(from: token),
           tokens.indices.contains(index + 1),
           isStarToken(tokens[index + 1]) {
            return (value, 2)
        }

        guard token == "rating" || token == "rated" else {
            return nil
        }

        if tokens.indices.contains(index + 2),
           normalizedToken(tokens[index + 1]) == ">=",
           let value = ratingValue(from: normalizedToken(tokens[index + 2])) {
            return (value, 3)
        }

        if tokens.indices.contains(index + 1),
           let value = compactRatingValue(from: normalizedToken(tokens[index + 1])) ?? ratingValue(from: normalizedToken(tokens[index + 1])) {
            return (value, 2)
        }

        return nil
    }

    private static func phrasePredicate(in tokens: [String], at index: Int) -> (
        predicate: SetQuery.Predicate,
        chip: String,
        namePart: String,
        consumedTokenCount: Int
    )? {
        let current = normalizedToken(tokens[index])

        if current == "unevaluated" || current == "unanalyzed" {
            return (.unevaluated, "Needs Evaluation", "Needs Evaluation", 1)
        }

        guard tokens.indices.contains(index + 1) else {
            return nil
        }

        let next = normalizedToken(tokens[index + 1])
        switch (current, next) {
        case ("needs", "keywords"), ("need", "keywords"), ("missing", "keywords"), ("without", "keywords"), ("no", "keywords"),
             ("needs", "keyword"), ("missing", "keyword"):
            return (.missingKeywords, "Needs Keywords", "Needs Keywords", 2)
        case ("needs", "evaluation"), ("need", "evaluation"), ("not", "evaluated"), ("needs", "analysis"), ("need", "analysis"),
             ("needs", "ai"), ("need", "ai"):
            return (.unevaluated, "Needs Evaluation", "Needs Evaluation", 2)
        default:
            return nil
        }
    }

    private static func compactRatingValue(from token: String) -> Int? {
        let compact = token
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        if compact.hasSuffix("stars") {
            return ratingValue(from: String(compact.dropLast(5)))
        }
        if compact.hasSuffix("star") {
            return ratingValue(from: String(compact.dropLast(4)))
        }
        if token.hasPrefix(">=") {
            return ratingValue(from: String(token.dropFirst(2)))
        }
        return nil
    }

    private static func ratingValue(from token: String) -> Int? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
        if let value = Int(cleaned), (1...5).contains(value) {
            return value
        }
        switch cleaned {
        case "one":
            return 1
        case "two":
            return 2
        case "three":
            return 3
        case "four":
            return 4
        case "five":
            return 5
        default:
            return nil
        }
    }

    private static func isStarToken(_ token: String) -> Bool {
        let normalized = normalizedToken(token)
        return normalized == "star" || normalized == "stars"
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func searchTokens(from text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quotedBy: Character?

        for character in text {
            if let quote = quotedBy {
                if character == quote {
                    quotedBy = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quotedBy = character
                continue
            }

            if isWhitespace(character) {
                appendCurrentToken(&current, to: &tokens)
            } else {
                current.append(character)
            }
        }

        appendCurrentToken(&current, to: &tokens)
        return tokens
    }

    private static func appendCurrentToken(_ current: inout String, to tokens: inout [String]) {
        let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            tokens.append(token)
        }
        current = ""
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?()[]{}\"'"))
            .lowercased()
    }

    private static func append(_ predicate: SetQuery.Predicate, to predicates: inout [SetQuery.Predicate]) {
        guard !predicates.contains(predicate) else { return }
        predicates.append(predicate)
    }

    private static func append(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private static func removeFlagPredicates(from predicates: inout [SetQuery.Predicate]) {
        predicates.removeAll { predicate in
            if case .flag = predicate {
                return true
            }
            return false
        }
    }

    private static func removeRatingPredicates(from predicates: inout [SetQuery.Predicate]) {
        predicates.removeAll { predicate in
            if case .ratingAtLeast = predicate {
                return true
            }
            return false
        }
    }
}
