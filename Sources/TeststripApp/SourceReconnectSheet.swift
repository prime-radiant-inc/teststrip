import SwiftUI

struct SourceReconnectSheet: View {
    @Binding var draft: SourceReconnectPathDraft
    var isImporting: Bool
    var cancel: () -> Void
    var reconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reconnect Source Root")
                .font(.headline)
            TextField("Old root path", text: $draft.oldRootPath)
                .textFieldStyle(.roundedBorder)
                .frame(width: 460)
            TextField("New mounted root path", text: $draft.newRootPath)
                .textFieldStyle(.roundedBorder)
                .frame(width: 460)
            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    cancel()
                }
                Button("Reconnect") {
                    reconnect()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.oldRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draft.newRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isImporting)
            }
        }
        .padding(18)
    }
}
