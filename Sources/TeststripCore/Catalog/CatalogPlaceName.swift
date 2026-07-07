import Foundation

/// A cached reverse-geocoded place name for a rounded coordinate key. Display-only
/// derived data: it lives solely in `place_cache`, never on `AssetMetadata`, and
/// clearing it and re-running is always safe.
public struct CatalogPlaceName: Equatable, Sendable {
    public var coordinateKey: String
    public var locality: String?
    public var administrativeArea: String?
    public var country: String?
    public var displayName: String?

    public init(
        coordinateKey: String,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        displayName: String? = nil
    ) {
        self.coordinateKey = coordinateKey
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.country = country
        self.displayName = displayName
    }

    /// The one place display names are composed, so the geocode writer and the
    /// TOP LOCATIONS aggregation agree. Uses the most specific of locality (else
    /// administrativeArea), joined with country by a middle dot (e.g.
    /// `Paris · France`); nil when every component is nil.
    public static func displayName(
        locality: String?,
        administrativeArea: String?,
        country: String?
    ) -> String? {
        let place = firstNonEmpty(locality) ?? firstNonEmpty(administrativeArea)
        let nation = firstNonEmpty(country)
        let parts = [place, nation].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func firstNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
