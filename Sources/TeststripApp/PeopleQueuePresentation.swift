import TeststripCore

/// One focusable entry in the People queue: either a face-suggestion card
/// ("Is this X?" / "Who is this?") or a review card ("Unnamed faces" /
/// "Face quality"). Folding both into one queue lets a single keyboard
/// flow (←/→ focus, Return confirm, Esc dismiss) drive the whole People
/// screen instead of requiring separate mouse interactions per section.
enum PeopleQueueCardKind: Equatable {
    case suggestion(PeopleFaceSuggestionCard)
    case review(PeopleReviewCard)
}

struct PeopleQueueCard: Equatable, Identifiable {
    var id: String
    var kind: PeopleQueueCardKind

    init(id: String, kind: PeopleQueueCardKind) {
        self.id = id
        self.kind = kind
    }
}

enum PeopleQueueFocusDirection: Equatable, Sendable {
    case next
    case previous
}

/// Keyboard-driven focus model over the People queue. ←/→ move focus with
/// wrapping; Return is the explicit write gesture that confirms only the
/// focused card (never any other card, and never on Space); Esc dismisses
/// the focused card when dismissal is possible, otherwise it is a no-op.
struct PeopleQueuePresentation: Equatable {
    var cards: [PeopleQueueCard]
    var focusedIndex: Int

    init(
        suggestionCards: [PeopleFaceSuggestionCard],
        reviewCards: [PeopleReviewCard],
        focusedIndex: Int = 0
    ) {
        var cards = suggestionCards.map { PeopleQueueCard(id: $0.id, kind: .suggestion($0)) }
        cards += reviewCards.map { PeopleQueueCard(id: $0.id, kind: .review($0)) }
        self.cards = cards
        self.focusedIndex = cards.isEmpty ? 0 : min(max(focusedIndex, 0), cards.count - 1)
    }

    var focusedCard: PeopleQueueCard? {
        guard cards.indices.contains(focusedIndex) else { return nil }
        return cards[focusedIndex]
    }

    func movingFocus(_ direction: PeopleQueueFocusDirection) -> PeopleQueuePresentation {
        guard !cards.isEmpty else { return self }
        var copy = self
        switch direction {
        case .next:
            copy.focusedIndex = (focusedIndex + 1) % cards.count
        case .previous:
            copy.focusedIndex = (focusedIndex - 1 + cards.count) % cards.count
        }
        return copy
    }

    /// What Return should do to the focused card, and only the focused
    /// card — the explicit write gesture. One-tap suggestions confirm
    /// directly; suggestions that need a name route to the naming sheet
    /// instead of writing immediately; review cards route to their queue.
    func confirmAction() -> PeopleQueueConfirmAction {
        guard let focusedCard else { return .none }
        switch focusedCard.kind {
        case .suggestion(let card):
            return card.isOneTapConfirm ? .confirmSuggestion(card.suggestion) : .nameSuggestion(card.suggestion)
        case .review(let card):
            guard let target = card.target else { return .none }
            return .selectReview(target)
        }
    }

    /// What Esc should do to the focused card: dismiss it when dismissal is
    /// possible (suggestion cards), otherwise nothing — Esc never writes.
    func dismissAction() -> PeopleQueueDismissAction {
        guard let focusedCard else { return .none }
        switch focusedCard.kind {
        case .suggestion(let card):
            return .dismissSuggestion(card.suggestion)
        case .review:
            return .none
        }
    }
}

enum PeopleQueueConfirmAction: Equatable {
    case confirmSuggestion(PeopleFaceSuggestion)
    case nameSuggestion(PeopleFaceSuggestion)
    case selectReview(SidebarRowTarget)
    case none
}

enum PeopleQueueDismissAction: Equatable {
    case dismissSuggestion(PeopleFaceSuggestion)
    case none
}
