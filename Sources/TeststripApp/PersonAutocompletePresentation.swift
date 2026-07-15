import Foundation
import TeststripCore

struct PersonAutocompleteRow: Equatable {
    enum Kind: Equatable {
        case person(PersonCandidate)
        case create(name: String)
    }
    let kind: Kind
}

enum PersonAutocompletePresentation {
    static func rows(candidates: [PersonCandidate], query: String) -> [PersonAutocompleteRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? candidates
            : candidates.filter { $0.name.range(of: trimmed, options: .caseInsensitive) != nil }
        var rows = filtered.map { PersonAutocompleteRow(kind: .person($0)) }
        if !trimmed.isEmpty,
           !candidates.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            rows.append(PersonAutocompleteRow(kind: .create(name: trimmed)))
        }
        return rows
    }

    static func clampedFocusIndex(_ index: Int, rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        return ((index % rowCount) + rowCount) % rowCount
    }
}
