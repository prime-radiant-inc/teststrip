import SwiftUI
import TeststripCore

/// The app's Settings (⌘,) window. Currently a single place to set the default
/// byline — a photographer's Creator/Copyright is the same on every frame, so
/// they type it once here and it pre-fills (never auto-writes) the metadata
/// fields when captioning.
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
