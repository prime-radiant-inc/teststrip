import Foundation
import TeststripCore

/// Persists user-editable export presets and the last-used preset name.
/// Presets are small value blobs scoped to the app, not the catalog (export
/// settings aren't a property of any one photo library), so this mirrors
/// FolderSelectionPanel's UserDefaults-backed remembered-folder pattern
/// rather than adding a catalog table.
enum ExportPresetStore {
    private static let presetsKey = "ExportPresetStore.presets"
    private static let lastUsedPresetNameKey = "ExportPresetStore.lastUsedPresetName"

    static func loadPresets(defaults: UserDefaults = .standard) -> [ExportPreset] {
        guard let data = defaults.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([ExportPreset].self, from: data),
              !decoded.isEmpty else {
            return ExportPreset.all
        }
        return decoded
    }

    static func savePresets(_ presets: [ExportPreset], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: presetsKey)
    }

    static func lastUsedPresetName(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: lastUsedPresetNameKey)
    }

    static func rememberLastUsedPreset(named name: String, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: lastUsedPresetNameKey)
    }

    static func lastUsedPreset(in presets: [ExportPreset], defaults: UserDefaults = .standard) -> ExportPreset? {
        guard let name = lastUsedPresetName(defaults: defaults) else { return nil }
        return presets.first { $0.name == name }
    }
}

/// Pure list-editing helpers behind the popover's "+ New Preset" and delete
/// actions, factored out so they're testable without SwiftUI state.
enum ExportPresetListEditing {
    static func upserting(_ preset: ExportPreset, into presets: [ExportPreset]) -> [ExportPreset] {
        var result = presets
        if let index = result.firstIndex(where: { $0.name == preset.name }) {
            result[index] = preset
        } else {
            result.append(preset)
        }
        return result
    }

    static func removing(named name: String, from presets: [ExportPreset]) -> [ExportPreset] {
        guard presets.count > 1 else { return presets }
        return presets.filter { $0.name != name }
    }
}
