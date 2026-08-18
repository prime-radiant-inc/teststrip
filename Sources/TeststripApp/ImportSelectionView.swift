import SwiftUI
import TeststripCore

enum ImportSelectionFilter: Hashable {
    case all
    case newOnly
    case duplicates
}

struct ImportSelectionEntry: Identifiable, Hashable {
    let url: URL
    let byteSize: Int64
    let isDuplicate: Bool

    var id: URL { url }
}

@MainActor
final class ImportSelectionModel: ObservableObject {
    let entries: [ImportSelectionEntry]
    let duplicateURLs: Set<URL>
    let thumbnailCache: PreIngestThumbnailCache
    let thumbnailRenderer: PreIngestThumbnailRenderer

    @Published var selectedURLs: Set<URL>
    @Published var filter: ImportSelectionFilter = .all
    @Published var thumbnails: [URL: NSImage] = [:]
    @Published var isRendering = false

    init(
        entries: [ImportSelectionEntry],
        duplicateURLs: Set<URL>,
        thumbnailCache: PreIngestThumbnailCache = PreIngestThumbnailCache(),
        thumbnailRenderer: PreIngestThumbnailRenderer = PreIngestThumbnailRenderer()
    ) {
        self.entries = entries
        self.duplicateURLs = duplicateURLs
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
        self.selectedURLs = Set(entries.map(\.url))
    }

    var filteredEntries: [ImportSelectionEntry] {
        switch filter {
        case .all:
            entries
        case .newOnly:
            entries.filter { !duplicateURLs.contains($0.url) }
        case .duplicates:
            entries.filter { duplicateURLs.contains($0.url) }
        }
    }

    var selectedCount: Int { selectedURLs.count }

    func selectAll() {
        selectedURLs = Set(entries.map(\.url))
    }

    func selectNone() {
        selectedURLs.removeAll()
    }

    func toggle(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    func loadThumbnail(for url: URL) {
        if thumbnails[url] != nil { return }
        if let data = thumbnailCache.thumbnailData(for: url), let image = NSImage(data: data) {
            thumbnails[url] = image
            return
        }
        isRendering = true
        let cache = thumbnailCache
        let renderer = thumbnailRenderer
        Task.detached {
            try? renderer.render(sourceURL: url, cache: cache)
            let data = cache.thumbnailData(for: url)
            await MainActor.run {
                if let data, let image = NSImage(data: data) {
                    self.thumbnails[url] = image
                }
                self.isRendering = false
            }
        }
    }
}

struct ImportSelectionView: View {
    @StateObject var model: ImportSelectionModel
    let onConfirm: (Set<URL>) -> Void
    let onCancel: () -> Void

    private let columns = Array(
        repeating: GridItem(.adaptive(minimum: 100), spacing: 8),
        count: 1
    )

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("Filter", selection: $model.filter) {
                    Text("All").tag(ImportSelectionFilter.all)
                    Text("New").tag(ImportSelectionFilter.newOnly)
                    Text("Duplicates").tag(ImportSelectionFilter.duplicates)
                }
                .pickerStyle(.segmented)
                Spacer()
                Text("\(model.selectedCount) of \(model.entries.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            // Thumbnail grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.filteredEntries) { entry in
                        ThumbnailCell(
                            entry: entry,
                            isSelected: model.selectedURLs.contains(entry.url),
                            thumbnail: model.thumbnails[entry.url],
                            isDuplicate: model.duplicateURLs.contains(entry.url),
                            onToggle: { model.toggle(entry.url) },
                            onAppear: { model.loadThumbnail(for: entry.url) }
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            // Footer
            HStack {
                Button("Select All") { model.selectAll() }
                Button("Select None") { model.selectNone() }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                Button("Import \(model.selectedCount) Photos") {
                    onConfirm(model.selectedURLs)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedURLs.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 800, height: 600)
    }
}

private struct ThumbnailCell: View {
    let entry: ImportSelectionEntry
    let isSelected: Bool
    let thumbnail: NSImage?
    let isDuplicate: Bool
    let onToggle: () -> Void
    let onAppear: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )

                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(4)

                // Duplicate badge
                if isDuplicate {
                    Text("Dup")
                        .font(.caption2)
                        .padding(2)
                        .background(.orange.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { onAppear() }
    }
}
