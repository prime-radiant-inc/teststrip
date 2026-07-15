import SwiftUI
import TeststripCore

struct PeopleView: View {
    var model: AppModel

    @State private var isNamingSelection = false
    @State private var personName = ""
    @State private var namingSuggestion: PeopleFaceSuggestion?
    @State private var suggestionPersonName = ""
    // The face group currently open in the review surface, tracked by
    // suggestion id (not the value) so the review view always re-reads the
    // live, possibly-shrunk suggestion from the model.
    @State private var reviewingGroup: ReviewingFaceGroup?
    // persona-2 item 3: the naming field didn't visually announce itself as
    // typeable — Ruth had to hunt before typing blindly. Auto-focus it so
    // typing works immediately and a focus ring is visible on appear.
    @FocusState private var isSuggestionNameFieldFocused: Bool
    @State private var queueFocusedIndex = 0
    @State private var keyCaptureFocusRequest = 0

    private var presentation: PeoplePresentation {
        PeoplePresentation(
            totalAssetCount: model.totalAssetCount,
            namedPeople: model.catalogPeople,
            evaluationSummaries: model.catalogEvaluationKindSummaries,
            canRequestCurrentScopeFaceScan: model.canRequestPeopleFaceScan,
            faceSuggestions: model.peopleFaceSuggestions,
            faceObservationAssetCount: model.peopleFaceObservationAssetCount,
            hasUnavailableSources: model.hasUnavailableSourceRoots
        )
    }

    // Folds suggestion cards and review cards into one keyboard-focusable
    // queue (Task 21). ←/→ move `queueFocusedIndex`; Return confirms only
    // the focused card via PeopleQueuePresentation.confirmAction().
    private var queuePresentation: PeopleQueuePresentation {
        PeopleQueuePresentation(
            suggestionCards: presentation.suggestionCards,
            reviewCards: presentation.reviewCards,
            focusedIndex: queueFocusedIndex
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
        .overlay(alignment: .topLeading) {
            PeopleKeyCaptureView(
                focusRequest: keyCaptureFocusRequest,
                onCommand: handleQueueCommand
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .task {
            model.refreshPeopleFaceSuggestions()
        }
        .onAppear {
            keyCaptureFocusRequest += 1
        }
        .sheet(isPresented: $isNamingSelection) {
            nameSelectionSheet
        }
        .sheet(item: $namingSuggestion) { suggestion in
            nameSuggestionSheet(suggestion)
        }
        .sheet(item: $reviewingGroup) { group in
            faceGroupReviewSheet(group.id)
        }
        .liveMockupPlaceholder(.peopleSidebar)
    }

    private func handleQueueCommand(_ command: PeopleQueueCommand) {
        let queue = queuePresentation
        switch command {
        case .moveFocus(let direction):
            let moved = queue.movingFocus(direction)
            queueFocusedIndex = moved.focusedIndex
        case .confirmFocused:
            applyConfirmAction(queue.confirmAction())
        case .dismissFocused:
            applyDismissAction(queue.dismissAction())
            queueFocusedIndex = queue.focusAfterEscape().focusedIndex
        }
    }

    private func applyConfirmAction(_ action: PeopleQueueConfirmAction) {
        switch action {
        case .confirmSuggestion(let suggestion):
            do {
                try model.confirmPeopleFaceSuggestion(suggestion)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        case .nameSuggestion(let suggestion):
            suggestionPersonName = ""
            namingSuggestion = suggestion
        case .selectReview(let target):
            do {
                try model.selectSidebarTarget(target)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        case .none:
            break
        }
    }

    private func applyDismissAction(_ action: PeopleQueueDismissAction) {
        switch action {
        case .dismissSuggestion(let suggestion):
            do {
                try model.dismissPeopleFaceSuggestion(suggestion)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        case .none:
            break
        }
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
                Image(systemName: DesignGlyph.ai.symbolName)
                    .foregroundStyle(.orange)
                Text(presentation.reviewStripTitle)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                Text(presentation.reviewStripStatusText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(presentation.reviewStripDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            // The scan trigger lives in the People ▸ Scan for Faces menu
            // (Task 21) — no button on this canvas — and its progress
            // reports through the Activity item like any other evaluation
            // pass. `presentation.scanAction` still gates whether scanning
            // is currently possible; its detail text now surfaces here.
            if let scanAction = presentation.scanAction {
                Text(scanAction.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !presentation.suggestionCards.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(presentation.suggestionCards) { card in
                        faceSuggestionCard(card, isFocused: isQueueFocused(cardID: card.id))
                    }
                }
            }

            if presentation.reviewCards.isEmpty {
                Text(presentation.faceReviewEmptyPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(presentation.reviewCards) { card in
                        Button {
                            selectPeopleReviewCard(card)
                        } label: {
                            peopleReviewCard(card, isFocused: isQueueFocused(cardID: card.id))
                        }
                        .buttonStyle(.plain)
                        .disabled(!card.isActionEnabled)
                        .help(card.isActionEnabled ? card.suggestedActionTitle : "Face naming is not built yet")
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
            Text(presentation.namedPeopleTitle)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                personName = ""
                isNamingSelection = true
            } label: {
                Label("Name selection", systemImage: "person.crop.circle.badge.plus")
            }
            .controlSize(.small)
            .disabled(!model.canConfirmSelectedPerson)
            .help(model.canConfirmSelectedPerson ? "Create a confirmed person group from the selected photos" : "Select photos before naming a person")

            Button {
                dismissSelectedFaceReviewAssets()
            } label: {
                Label("Dismiss face review", systemImage: "eye.slash")
            }
            .controlSize(.small)
            .disabled(!model.canDismissSelectedFaceReviewAssets)
            .help(model.canDismissSelectedFaceReviewAssets ? "Remove the selected photos from People face-review queues" : "Select photos before dismissing face review")

            if presentation.namedPeople.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(avatarGradient(seed: "pending-face-groups", colors: [.orange, .brown]))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.12))
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("No confirmed people yet")
                            .font(.headline.weight(.semibold))
                        Text(presentation.namedPeopleEmptyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(presentation.faceActionStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .liveMockupPlaceholder(.peopleFaceActions)
                    }
                }
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.07))
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(presentation.namedPeople) { person in
                        namedPersonCard(person)
                    }
                }
            }
        }
    }

    private var nameSelectionSheet: some View {
        SheetScaffold(
            title: "Name Selection",
            // The count keeps a stale cross-workspace selection visible
            // before the confirming click (persona-6: a leftover Library
            // selection misfiled a person with no hint of what it covered).
            subtitle: PeoplePresentation.nameSelectionSubtitle(
                selectedPhotoCount: model.selectedPeopleCandidateAssetCount
            ),
            width: 320,
            primaryLabel: "Create Person",
            isPrimaryEnabled: !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            cancel: { isNamingSelection = false },
            primary: confirmSelectedPerson
        ) {
            TextField("Person name", text: $personName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func confirmSelectedPerson() {
        do {
            try model.confirmSelectedAssetsAsPerson(named: personName)
            isNamingSelection = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func isQueueFocused(cardID: String) -> Bool {
        queuePresentation.focusedCard?.id == cardID
    }

    // A suggestion card is a link into the review surface — click it to look
    // at every face in the group large and zoomed before naming (review-first),
    // rather than confirming a whole group from one tiny crop. Confirm/Name
    // live inside the review surface now; the card keeps only Review + Dismiss.
    private func faceSuggestionCard(_ card: PeopleFaceSuggestionCard, isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                openFaceGroupReview(card)
            } label: {
                HStack(spacing: 12) {
                    FaceCropAvatar(
                        previewURL: model.previewURL(for: card.suggestion.representativeFace.assetID, levels: [.grid, .medium, .micro]),
                        boundingBox: card.suggestion.representativeBoundingBox
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.countText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(card.title)
                            .font(.caption.weight(.semibold))
                        Label("Review", systemImage: "rectangle.stack.badge.person.crop")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(card.isOneTapConfirm ? "Review this group before confirming \(card.confirmActionTitle)" : "Review these faces before naming them")

            Button {
                dismissFaceSuggestion(card)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss this face group")
        }
        .padding(12)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isFocused ? Color.accentColor : Color.white.opacity(0.07), lineWidth: isFocused ? 2 : 1)
        }
    }

    private func nameSuggestionSheet(_ suggestion: PeopleFaceSuggestion) -> some View {
        SheetScaffold(
            title: "Name Face Group",
            subtitle: PeoplePresentation.nameFaceGroupSubtitle(
                faceCount: suggestion.faceIDs.count,
                photoCount: suggestion.assetIDs.count
            ),
            width: 320,
            primaryLabel: "Create Person",
            isPrimaryEnabled: !suggestionPersonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            cancel: { namingSuggestion = nil },
            primary: { confirmNamedFaceSuggestion(suggestion) }
        ) {
            TextField("Person name", text: $suggestionPersonName)
                .textFieldStyle(.roundedBorder)
                .focused($isSuggestionNameFieldFocused)
                .onAppear { isSuggestionNameFieldFocused = true }
        }
    }

    private func openFaceGroupReview(_ card: PeopleFaceSuggestionCard) {
        reviewingGroup = ReviewingFaceGroup(id: card.id)
    }

    private func faceGroupReviewSheet(_ suggestionID: String) -> some View {
        FaceGroupReviewView(
            model: model,
            suggestionID: suggestionID,
            confirm: { suggestion in
                do {
                    try model.confirmPeopleFaceSuggestion(suggestion)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
                reviewingGroup = nil
            },
            name: { suggestion in
                reviewingGroup = nil
                suggestionPersonName = ""
                namingSuggestion = suggestion
            },
            close: { reviewingGroup = nil }
        )
    }

    private func confirmNamedFaceSuggestion(_ suggestion: PeopleFaceSuggestion) {
        do {
            try model.confirmPeopleFaceSuggestion(suggestion, personName: suggestionPersonName)
            namingSuggestion = nil
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func dismissFaceSuggestion(_ card: PeopleFaceSuggestionCard) {
        do {
            try model.dismissPeopleFaceSuggestion(card.suggestion)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func namedPersonCard(_ person: NamedPersonPresentation) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarGradient(seed: person.id, colors: [.orange, .pink]))
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(person.name)
                    .font(.headline.weight(.semibold))
                Text(person.countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if presentation.namedPeople.count > 1 {
                Menu {
                    ForEach(presentation.namedPeople.filter { $0.id != person.id }) { target in
                        Button("Merge into \(target.name)") {
                            mergePerson(person, into: target)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.merge")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Merge this person into another confirmed group")
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.07))
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            showPersonPhotos(person)
        }
        .help("Show \(person.name)'s confirmed photos in the library grid")
    }

    private func showPersonPhotos(_ person: NamedPersonPresentation) {
        do {
            try model.showPersonPhotos(named: person.name)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func peopleReviewCard(_ card: PeopleReviewCard, isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarGradient(seed: card.id, colors: card.gradientColors))
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(card.countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(card.suggestedActionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.isActionEnabled ? .primary : .secondary)
                    if card.showsUnbuiltFaceActionLock {
                        Image(systemName: "lock")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .liveMockupPlaceholder(.peopleFaceActions)
                    }
                }
                Text(card.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if card.isActionEnabled {
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isFocused ? Color.accentColor : Color.white.opacity(0.07), lineWidth: isFocused ? 2 : 1)
        }
    }

    private func selectPeopleReviewCard(_ card: PeopleReviewCard) {
        guard let target = card.target else { return }
        do {
            try model.selectSidebarTarget(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func mergePerson(_ person: NamedPersonPresentation, into target: NamedPersonPresentation) {
        do {
            try model.mergePerson(sourceID: person.id, into: target.id)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func dismissSelectedFaceReviewAssets() {
        do {
            try model.dismissSelectedFaceReviewAssets()
        } catch {
            model.errorMessage = error.localizedDescription
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

/// Identifies the face group open in the review sheet by suggestion id, so the
/// `.sheet(item:)` presentation drives off a stable key while the review view
/// re-reads the live suggestion.
struct ReviewingFaceGroup: Identifiable, Equatable {
    var id: String
}

struct PeoplePresentation: Equatable {
    var totalAssetCount: Int
    var namedPeople: [NamedPersonPresentation]
    var photosWithFaceSignals: Int
    var photosWithDetectedFaces: Int
    var photosWithFaceQualitySignals: Int
    var scanAction: PeopleScanAction?
    var faceSuggestions: [PeopleFaceSuggestion]
    var faceObservationAssetCount: Int
    /// True when any catalog source root is offline/unreachable — a face
    /// scan requested now cannot enqueue work, so the status line must say
    /// so instead of "Scan ready" (persona-6: the banner sat on "Scan
    /// ready" forever while nothing could ever start).
    var hasUnavailableSources: Bool
    private var faceSignalKind: EvaluationKind?

    init(
        totalAssetCount: Int,
        namedPeople: [CatalogPerson] = [],
        evaluationSummaries: [CatalogEvaluationKindSummary],
        canRequestCurrentScopeFaceScan: Bool = false,
        faceSuggestions: [PeopleFaceSuggestion] = [],
        faceObservationAssetCount: Int = 0,
        hasUnavailableSources: Bool = false
    ) {
        self.hasUnavailableSources = hasUnavailableSources
        self.totalAssetCount = totalAssetCount
        self.namedPeople = namedPeople.map { NamedPersonPresentation(person: $0) }
        let faceCountSignals = evaluationSummaries.first { $0.kind == .faceCount }?.assetCount ?? 0
        let faceQualitySignals = evaluationSummaries.first { $0.kind == .faceQuality }?.assetCount ?? 0
        self.photosWithFaceSignals = max(faceCountSignals, faceQualitySignals)
        self.photosWithDetectedFaces = faceCountSignals > 0 ? faceCountSignals : faceQualitySignals
        self.photosWithFaceQualitySignals = faceQualitySignals
        self.faceSignalKind = faceCountSignals > 0 ? .faceCount : (faceQualitySignals > 0 ? .faceQuality : nil)
        self.scanAction = canRequestCurrentScopeFaceScan ? PeopleScanAction(
            title: "Scan for Faces",
            detail: "Runs local Apple Vision on cached previews for these photos. If a photo's detected faces change, its confirmed and dismissed faces are cleared for re-review.",
            systemImage: "viewfinder"
        ) : nil
        self.faceSuggestions = faceSuggestions
        self.faceObservationAssetCount = faceObservationAssetCount
    }

    /// "Name Selection" sheet subtitle: names how many photos the confirming
    /// click will attach, so a stale cross-workspace selection is visible
    /// before the write.
    static func nameSelectionSubtitle(selectedPhotoCount: Int) -> String {
        let noun = selectedPhotoCount == 1 ? "photo" : "photos"
        return "Groups the \(selectedPhotoCount) selected \(noun) under a new named person."
    }

    /// "Name Face Group" sheet subtitle with the group's face and photo counts.
    static func nameFaceGroupSubtitle(faceCount: Int, photoCount: Int) -> String {
        let faceNoun = faceCount == 1 ? "face" : "faces"
        let photoNoun = photoCount == 1 ? "photo" : "photos"
        return "Groups this face group's \(faceCount) \(faceNoun) across \(photoCount) \(photoNoun) under a new named person."
    }

    var headerSummary: String {
        if !namedPeople.isEmpty {
            return "\(namedPeople.count) people · \(photosWithFaceSignals) photos with face signals"
        }
        if photosWithFaceSignals > 0 {
            return "0 people · \(photosWithFaceSignals) photos with face signals"
        }
        return "0 people · \(totalAssetCount) photos"
    }

    var statusTitle: String {
        photosWithFaceSignals > 0 ? "Faces to review" : "No faces found yet"
    }

    var statusDetail: String {
        if photosWithFaceSignals > 0 {
            return "Review \(photosWithFaceSignals) photos with unnamed face signals. Select photos, then name the selection."
        }
        return "Scan these photos to find faces to review."
    }

    var reviewStripTitle: String {
        if !faceSuggestions.isEmpty {
            let totalFaces = faceSuggestions.reduce(0) { $0 + $1.faceIDs.count }
            return totalFaces == 1
                ? "1 face needs a name"
                : "\(totalFaces) faces need a name"
        }
        guard photosWithFaceSignals > 0 else {
            return "No faces found yet"
        }
        return "\(Self.photoCountDescription(photosWithDetectedFaces)) need face review"
    }

    var reviewStripStatusText: String {
        if !faceSuggestions.isEmpty {
            let matchCount = faceSuggestions.filter { $0.kind != .newPerson }.count
            if matchCount > 0 {
                return matchCount == 1
                    ? "1 group matches confirmed people"
                    : "\(matchCount) groups match confirmed people"
            }
            let clusterCount = faceSuggestions.count
            return clusterCount == 1 ? "1 new group" : "\(clusterCount) new groups"
        }
        let reviewQueueCount = reviewCards.count
        if reviewQueueCount > 0 {
            return reviewQueueCount == 1 ? "1 queue" : "\(reviewQueueCount) queues"
        }
        if hasUnavailableSources {
            return "Photo sources offline — reconnect to scan"
        }
        if scanAction != nil {
            return "Scan ready"
        }
        return "0 queues"
    }

    var reviewStripDetail: String {
        if !faceSuggestions.isEmpty {
            return "Face groups are provisional until you confirm. Confirming writes people to the catalog; dismissing hides the group."
        }
        guard photosWithFaceSignals > 0 else {
            return "These photos haven’t been scanned for faces yet. Scan for faces to see who’s in your photos."
        }
        if faceObservationAssetCount == 0 {
            return "Face signals predate grouping; run Scan for Faces to compute face embeddings."
        }
        if photosWithFaceQualitySignals > 0 {
            return "\(Self.photoCountDescription(photosWithFaceQualitySignals)) have face-quality signals; review queues can be named from selected photos."
        }
        return "\(Self.photoCountDescription(photosWithDetectedFaces)) have local face detections; review queues can be named from selected photos."
    }

    var suggestionCards: [PeopleFaceSuggestionCard] {
        faceSuggestions.map { suggestion in
            let faces = suggestion.faceIDs.count
            let photos = suggestion.assetIDs.count
            let countText = "\(faces) \(faces == 1 ? "face" : "faces") · \(photos) \(photos == 1 ? "photo" : "photos")"
            switch suggestion.kind {
            case .matchExisting(_, let personName):
                return PeopleFaceSuggestionCard(
                    id: suggestion.id,
                    title: "Is this \(personName)?",
                    countText: countText,
                    confirmActionTitle: personName,
                    isOneTapConfirm: true,
                    suggestion: suggestion
                )
            case .newPerson:
                return PeopleFaceSuggestionCard(
                    id: suggestion.id,
                    title: "Who is this?",
                    countText: countText,
                    confirmActionTitle: "Name…",
                    isOneTapConfirm: false,
                    suggestion: suggestion
                )
            }
        }
    }

    var reviewCards: [PeopleReviewCard] {
        var cards: [PeopleReviewCard] = []
        if photosWithDetectedFaces > 0, let faceSignalKind {
            cards.append(PeopleReviewCard(
                id: "unnamed-faces",
                title: "Unnamed faces",
                countText: Self.photoCountDescription(photosWithDetectedFaces),
                suggestedActionTitle: "Review faces",
                filterKind: faceSignalKind,
                target: faceSignalKind == .faceCount ? .reviewQueue(.facesFound) : .evaluationKind(faceSignalKind),
                gradientColors: [.orange, .brown]
            ))
        }
        if photosWithFaceQualitySignals > 0 {
            cards.append(PeopleReviewCard(
                id: "face-quality",
                title: "Face quality checks",
                countText: Self.photoCountDescription(photosWithFaceQualitySignals),
                suggestedActionTitle: "Review quality",
                filterKind: .faceQuality,
                target: .evaluationKind(.faceQuality),
                gradientColors: [.orange, .yellow]
            ))
        }
        return cards
    }

    var namedPeopleTitle: String {
        "ALL PEOPLE"
    }

    var namedPeopleEmptyText: String {
        if photosWithFaceSignals > 0 {
            return "No confirmed people yet. Review face queues, select photos, then name the selection."
        }
        return "Once Teststrip finds faces, name them here."
    }

    /// The prompt shown beside the Scan control when no face review queues exist
    /// yet. Deliberately distinct from `namedPeopleEmptyText` so the same
    /// sentence never renders twice on the People screen.
    var faceReviewEmptyPrompt: String {
        if photosWithFaceSignals > 0 {
            return "Review the face queues above, then name people here."
        }
        return "Scan to find faces in these photos."
    }

    var signalRows: [PeopleSignalRow] {
        [
            PeopleSignalRow(
                id: "face-count",
                title: "Unnamed faces",
                detail: "Review assets with local face detections",
                countText: "\(photosWithDetectedFaces)",
                systemImage: "person.crop.rectangle.stack",
                filterKind: faceSignalKind
            ),
            PeopleSignalRow(
                id: "face-quality",
                title: "Face quality review",
                detail: "Review assets with face-quality measurements",
                countText: "\(photosWithFaceQualitySignals)",
                systemImage: "face.smiling",
                filterKind: photosWithFaceQualitySignals > 0 ? .faceQuality : nil
            )
        ]
    }

    var visibleDeferredFaceActionTitles: [String] {
        []
    }

    var faceActionStatus: String {
        "Confirm a suggested group, name faces yourself, or merge people. Nothing is saved until you confirm."
    }

    private static func photoCountDescription(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }
}

struct PeopleSignalRow: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var countText: String
    var systemImage: String
    var filterKind: EvaluationKind?

    var isActionEnabled: Bool {
        filterKind != nil
    }
}

struct PeopleScanAction: Equatable {
    var title: String
    var detail: String
    var systemImage: String
}

struct NamedPersonPresentation: Equatable, Identifiable {
    var id: String
    var name: String
    var assetCount: Int

    init(person: CatalogPerson) {
        self.id = person.id
        self.name = person.name
        self.assetCount = person.assetCount
    }

    var countText: String {
        assetCount == 1 ? "1 confirmed photo" : "\(assetCount) confirmed photos"
    }
}

struct PeopleFaceSuggestionCard: Equatable, Identifiable {
    var id: String
    var title: String
    var countText: String
    var confirmActionTitle: String
    var isOneTapConfirm: Bool
    var suggestion: PeopleFaceSuggestion
}

struct PeopleReviewCard: Equatable, Identifiable {
    var id: String
    var title: String
    var countText: String
    var suggestedActionTitle: String
    var filterKind: EvaluationKind?
    var target: SidebarRowTarget?
    var showsUnbuiltFaceActionLock = false
    var gradientColors: [Color]

    var isActionEnabled: Bool {
        target != nil
    }
}
