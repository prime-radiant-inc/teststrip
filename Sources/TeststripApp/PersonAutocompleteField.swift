import SwiftUI
import TeststripCore

/// A reusable name-entry field for assigning a person to a face: a text field
/// backed by a ranked, filtered list of existing people (Task 4's
/// `PersonAutocompletePresentation`) plus a trailing "create new person" row
/// when the typed name doesn't match anyone. Arrow keys move a focus
/// highlight through the rows; Return activates whichever row is focused.
struct PersonAutocompleteField: View {
    var candidates: [PersonCandidate]
    var onPick: (String) -> Void
    var onCreate: (String) -> Void

    @State private var query = ""
    @State private var focusIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var rows: [PersonAutocompleteRow] {
        PersonAutocompletePresentation.rows(candidates: candidates, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onAppear { isFieldFocused = true }
                .onChange(of: query) { focusIndex = 0 }
                .onKeyPress(.downArrow) {
                    focusIndex = PersonAutocompletePresentation.clampedFocusIndex(focusIndex + 1, rowCount: rows.count)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    focusIndex = PersonAutocompletePresentation.clampedFocusIndex(focusIndex - 1, rowCount: rows.count)
                    return .handled
                }
                .onKeyPress(.return) {
                    if rows.indices.contains(focusIndex) { activate(rows[focusIndex]) }
                    return .handled
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        rowButton(row, isFocused: index == focusIndex)
                    }
                }
            }
        }
    }

    private func rowButton(_ row: PersonAutocompleteRow, isFocused: Bool) -> some View {
        Button {
            activate(row)
        } label: {
            rowLabel(row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func rowLabel(_ row: PersonAutocompleteRow) -> some View {
        switch row.kind {
        case .person(let candidate):
            HStack {
                Text(candidate.name)
                if let percent = candidate.similarityPercent {
                    Spacer()
                    Text("\(percent)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .create(let name):
            Label("Create \"\(name)\"", systemImage: "plus")
        }
    }

    private func activate(_ row: PersonAutocompleteRow) {
        switch row.kind {
        case .person(let candidate):
            onPick(candidate.id)
        case .create(let name):
            onCreate(name)
        }
    }
}
