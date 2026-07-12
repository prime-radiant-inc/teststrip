import SwiftUI
import TeststripCore

/// Pure display logic for the Card import section of Preferences, kept out of
/// the view so it's testable without instantiating SwiftUI/AppKit.
enum CardImportPreferencePresentation {
    static func destinationDisplay(_ path: String) -> String {
        path.isEmpty ? "None" : path
    }

    static func showsClear(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let footer = "Pre-fills the destination for new card imports. Originals are copied — never moved — into dated folders (YYYY/YYYY-MM-DD)."
}

/// The app's Settings (⌘,) window. Currently a place to set the default
/// byline — a photographer's Creator/Copyright is the same on every frame, so
/// they type it once here and it pre-fills (never auto-writes) the metadata
/// fields when captioning — and the default card-import destination, which
/// pre-fills (never auto-starts) new card imports.
struct PreferencesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                TextField("Creator", text: $model.defaultCreator, prompt: Text("Your name / byline"))
                TextField("Copyright", text: $model.defaultCopyright, prompt: Text("© 2026 Your Name"))
            } header: {
                Text("Default byline")
            } footer: {
                Text("Pre-fills the Creator and Copyright fields when you caption photos. Nothing is written to a photo until you apply it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Destination", value: CardImportPreferencePresentation.destinationDisplay(model.defaultCardImportDestination))
                HStack {
                    Button("Choose…") {
                        if let url = FolderSelectionPanel.chooseCardDestinationFolder() {
                            model.defaultCardImportDestination = url.path
                        }
                    }
                    if CardImportPreferencePresentation.showsClear(model.defaultCardImportDestination) {
                        Button("Clear") {
                            model.defaultCardImportDestination = ""
                        }
                    }
                }
            } header: {
                Text("Card import")
            } footer: {
                Text(CardImportPreferencePresentation.footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
