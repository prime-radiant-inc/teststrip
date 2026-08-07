/// The machine's flag opinion on an asset — the ✨ "ghost". An asset's
/// autopilot ghost is its flag label when the label is AI-origin and
/// unconfirmed; every proposal state (proposed / overridden / dismissed /
/// never applied) is derived from metadata here, never stored. There is no
/// status machine: a frame is allowed to have no status at all.
///
/// This is the single derivation source. No surface may re-derive ghost state
/// with its own metadata poking — the only other reader of the raw
/// representation is `CatalogRepository.assetIDsWithAutopilotGhost()`, the
/// catalog-wide SQL twin, whose tests pin it to agree with this function.
public enum AutopilotGhost {
    /// The ghost's kind — its own flag value — or `nil` when the asset carries
    /// no ghost (a user-origin flag, no flag at all, or only non-flag AI
    /// labels such as ambient keywords).
    public static func kind(in metadata: AssetMetadata) -> PickFlag? {
        guard metadata.aiUnconfirmedFields.contains(.flag) else { return nil }
        return metadata.flag
    }
}
