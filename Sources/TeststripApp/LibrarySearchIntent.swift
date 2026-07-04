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

        let tokens = normalized.split(separator: " ").map(String.init)
        var residualTokens: [String] = []
        var predicates: [SetQuery.Predicate] = []
        var chips: [String] = []
        var nameParts: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let normalizedToken = Self.normalizedToken(token)

            if let field = Self.fieldPredicate(from: token) {
                Self.append(field.predicate, to: &predicates)
                Self.append(field.chip, to: &chips)
                Self.append(field.namePart, to: &nameParts)
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

    private static func fieldPredicate(from token: String) -> (predicate: SetQuery.Predicate, chip: String, namePart: String)? {
        let separators = [":", "="]
        guard let separator = separators.first(where: { token.contains($0) }) else {
            return nil
        }
        let parts = token.split(separator: Character(separator), maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        let field = normalizedToken(String(parts[0]))
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        switch field {
        case "camera":
            return (.camera(value), "Camera: \(value)", value)
        case "lens":
            return (.lens(value), "Lens: \(value)", value)
        case "keyword", "tag":
            return (.keyword(value), "Keyword: \(value)", value)
        default:
            return nil
        }
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
