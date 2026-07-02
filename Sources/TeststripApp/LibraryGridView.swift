import AppKit
import SwiftUI
import TeststripCore
import UniformTypeIdentifiers

struct LibraryGridView: View {
    var model: AppModel
    @State private var isImportingFolder = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    private var isImporting: Bool {
        model.activeWork?.kind == .ingest && model.activeWork?.status == .running
    }

    var body: some View {
        ScrollView {
            if model.assets.isEmpty {
                emptyLibraryView
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.assets, id: \.id.rawValue) { asset in
                        Button {
                            model.select(asset.id)
                        } label: {
                            AssetGridCell(
                                asset: asset,
                                previewURL: model.gridPreviewURL(for: asset.id),
                                isSelected: model.selectedAssetID == asset.id
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .contentShape(Rectangle())
                        .accessibilityLabel(asset.originalURL.lastPathComponent)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("All Photographs")
        .toolbar {
            Button {
                isImportingFolder = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)
        }
        .fileImporter(
            isPresented: $isImportingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .background {
            CullingKeyCaptureView { shortcut in
                handleCullingShortcut(shortcut)
            }
        }
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No photographs in this catalog")
                .font(.headline)
            Button {
                isImportingFolder = true
            } label: {
                Label("Import Folder", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(32)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.libraryCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                Text("Importing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.hasMoreAssets {
                Button {
                    loadMoreAssets()
                } label: {
                    Label("Load More", systemImage: "arrow.down.circle")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(isImporting)
                .help("Load next photo page")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let folderURL = try result.get().first else { return }
            importFolder(folderURL)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func importFolder(_ folderURL: URL) {
        model.beginImportFolder(folderURL)
    }

    private func loadMoreAssets() {
        do {
            try model.loadMoreAssets()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func handleCullingShortcut(_ shortcut: CullingShortcut) {
        do {
            try model.applyCullingShortcut(shortcut)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct CullingKeyCaptureView: NSViewRepresentable {
    var onShortcut: (CullingShortcut) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShortcut: onShortcut)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onShortcut = onShortcut
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onShortcut: (CullingShortcut) -> Void
        private var monitor: Any?

        init(onShortcut: @escaping (CullingShortcut) -> Void) {
            self.onShortcut = onShortcut
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let view, event.window === view.window else { return event }
            guard event.window?.firstResponder is NSTextView == false else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            guard let key = shortcutKey(for: event), let shortcut = CullingShortcut(key: key) else {
                return event
            }
            onShortcut(shortcut)
            return nil
        }

        private func shortcutKey(for event: NSEvent) -> CullingShortcutKey? {
            switch event.keyCode {
            case 123:
                return .leftArrow
            case 124:
                return .rightArrow
            default:
                guard let character = event.charactersIgnoringModifiers, character.count == 1 else {
                    return nil
                }
                return .character(character)
            }
        }
    }
}

private struct AssetGridCell: View {
    var asset: Asset
    var previewURL: URL?
    var isSelected: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                thumbnail
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                metadataOverlay
                    .padding(6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.orange, lineWidth: 2)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.35))
            )
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let previewURL, let image = NSImage(contentsOf: previewURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.35))
        }
    }

    private var metadataOverlay: some View {
        HStack(spacing: 5) {
            if asset.metadata.flag == .pick {
                flagBadge(systemName: "flag.fill", color: .green)
            } else if asset.metadata.flag == .reject {
                flagBadge(systemName: "xmark", color: .red)
            }
            if asset.metadata.rating > 0 {
                Text(String(repeating: "★", count: asset.metadata.rating))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            if let colorLabel = asset.metadata.colorLabel {
                Circle()
                    .fill(color(for: colorLabel))
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
        }
    }

    private func flagBadge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: 15, height: 15)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func color(for label: ColorLabel) -> Color {
        switch label {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}
