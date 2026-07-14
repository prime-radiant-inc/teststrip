import Foundation

public enum ColorLabel: String, Codable, Sendable, CaseIterable {
    case red
    case yellow
    case green
    case blue
    case purple
}

public enum PickFlag: String, Codable, Sendable {
    case pick
    case reject
}

public enum MetadataField: String, Codable, Sendable, CaseIterable {
    case flag
    case caption
    case rating
    case keyword
}

public struct AssetMetadata: Codable, Equatable, Sendable {
    public var rating: Int {
        didSet {
            precondition(Self.isValidRating(rating), Self.invalidRatingMessage)
        }
    }
    public var colorLabel: ColorLabel?
    public var flag: PickFlag?
    public var keywords: [String]
    public var caption: String?
    public var creator: String?
    public var copyright: String?
    public var aiUnconfirmedKeywords: Set<String>
    public var aiUnconfirmedFields: Set<MetadataField>

    private enum CodingKeys: String, CodingKey {
        case rating
        case colorLabel
        case flag
        case keywords
        case caption
        case creator
        case copyright
        case aiUnconfirmedKeywords
        case aiUnconfirmedFields
    }

    private static let validRatingRange = 0...5
    private static let invalidRatingMessage = "rating must be between 0 and 5"

    /// A copy with every AI-unconfirmed label dropped — what is exported to the
    /// XMP sidecar and what "portable metadata exists" is judged against.
    public var confirmedProjection: AssetMetadata {
        AssetMetadata(
            rating: aiUnconfirmedFields.contains(.rating) ? 0 : rating,
            colorLabel: colorLabel,
            flag: aiUnconfirmedFields.contains(.flag) ? nil : flag,
            keywords: keywords.filter { !aiUnconfirmedKeywords.contains($0) },
            caption: aiUnconfirmedFields.contains(.caption) ? nil : caption,
            creator: creator,
            copyright: copyright
        )
    }

    /// Merges a freshly-parsed sidecar's confirmed labels into this (catalog)
    /// metadata. XMP never carries AI-unconfirmed markers (see
    /// `confirmedProjection`), so importing/freshening from a sidecar
    /// wholesale — `sidecarMetadata` as-is — would silently wipe any
    /// catalog-only AI proposal that hasn't been confirmed yet. This keeps
    /// the sidecar's confirmed values (they win for anything actually
    /// synced) while carrying this metadata's AI-unconfirmed state forward:
    /// unconfirmed keywords are added back into the merged keyword list, and
    /// an unconfirmed caption/flag/rating is restored from the catalog side
    /// only when the sidecar doesn't already carry that field/keyword — a
    /// confirmed sidecar value (e.g. set by an external tool like Lightroom)
    /// always wins over a stale unconfirmed AI one, and the field/keyword
    /// graduates to confirmed rather than staying marked unconfirmed.
    ///
    /// This assumes `XMPPacket` round-trips domain values losslessly — the
    /// `localChanged` no-op-detection in `MetadataSyncPlanner` depends on it.
    public func mergingConfirmedSidecar(_ sidecarMetadata: AssetMetadata) -> AssetMetadata {
        var merged = sidecarMetadata
        var keywords = sidecarMetadata.keywords
        for keyword in self.keywords where aiUnconfirmedKeywords.contains(keyword) && !keywords.contains(keyword) {
            keywords.append(keyword)
        }
        merged.keywords = keywords
        // A keyword the sidecar already carries is confirmed now, even if
        // the catalog still marked it unconfirmed; only catalog-only
        // proposals stay unconfirmed.
        merged.aiUnconfirmedKeywords = aiUnconfirmedKeywords.subtracting(sidecarMetadata.keywords)

        var unconfirmedFields = aiUnconfirmedFields
        if aiUnconfirmedFields.contains(.caption) {
            if merged.caption == nil {
                merged.caption = caption
            } else {
                unconfirmedFields.remove(.caption)
            }
        }
        if aiUnconfirmedFields.contains(.flag) {
            if merged.flag == nil {
                merged.flag = flag
            } else {
                unconfirmedFields.remove(.flag)
            }
        }
        if aiUnconfirmedFields.contains(.rating) {
            if merged.rating == 0 {
                merged.rating = rating
            } else {
                unconfirmedFields.remove(.rating)
            }
        }
        merged.aiUnconfirmedFields = unconfirmedFields
        return merged
    }

    /// True once the user has set any portable field that mirrors to an XMP
    /// sidecar. A sidecar is written only after such a set (non-destructive), so
    /// this doubles as "a sidecar exists for this asset" — used to show a
    /// positive "Saved to sidecar" confirmation when nothing is pending.
    public var hasWrittenPortableMetadata: Bool {
        let c = confirmedProjection
        return c.rating > 0
            || c.flag != nil
            || c.colorLabel != nil
            || !c.keywords.isEmpty
            || !(c.caption ?? "").isEmpty
            || !(c.creator ?? "").isEmpty
            || !(c.copyright ?? "").isEmpty
    }

    public init(
        rating: Int = 0,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        caption: String? = nil,
        creator: String? = nil,
        copyright: String? = nil,
        aiUnconfirmedKeywords: Set<String> = [],
        aiUnconfirmedFields: Set<MetadataField> = []
    ) {
        precondition(Self.isValidRating(rating), Self.invalidRatingMessage)

        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
        self.keywords = keywords
        self.caption = caption
        self.creator = creator
        self.copyright = copyright
        self.aiUnconfirmedKeywords = aiUnconfirmedKeywords
        self.aiUnconfirmedFields = aiUnconfirmedFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rating = try container.decode(Int.self, forKey: .rating)
        guard Self.isValidRating(rating) else {
            throw DecodingError.dataCorruptedError(
                forKey: .rating,
                in: container,
                debugDescription: Self.invalidRatingMessage
            )
        }

        self.rating = rating
        self.colorLabel = try container.decodeIfPresent(ColorLabel.self, forKey: .colorLabel)
        self.flag = try container.decodeIfPresent(PickFlag.self, forKey: .flag)
        self.keywords = try container.decode([String].self, forKey: .keywords)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.creator = try container.decodeIfPresent(String.self, forKey: .creator)
        self.copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
        self.aiUnconfirmedKeywords = try container.decodeIfPresent(Set<String>.self, forKey: .aiUnconfirmedKeywords) ?? []
        self.aiUnconfirmedFields = try container.decodeIfPresent(Set<MetadataField>.self, forKey: .aiUnconfirmedFields) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rating, forKey: .rating)
        try container.encodeIfPresent(colorLabel, forKey: .colorLabel)
        try container.encodeIfPresent(flag, forKey: .flag)
        try container.encode(keywords, forKey: .keywords)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(creator, forKey: .creator)
        try container.encodeIfPresent(copyright, forKey: .copyright)
        // Provenance sets are omitted when empty (keeps confirmed-only assets
        // byte-identical to the legacy canonical form) and encoded as sorted
        // arrays when present (Set iteration order is per-process random,
        // which would defeat the catalog's byte-stable metadata_json compare
        // used to detect real edits — see CatalogRepository's sortedKeys
        // encoder and catalog_generation bump logic).
        if !aiUnconfirmedKeywords.isEmpty {
            try container.encode(aiUnconfirmedKeywords.sorted(), forKey: .aiUnconfirmedKeywords)
        }
        if !aiUnconfirmedFields.isEmpty {
            try container.encode(
                aiUnconfirmedFields.sorted { $0.rawValue < $1.rawValue },
                forKey: .aiUnconfirmedFields
            )
        }
    }

    public static func validated(
        rating: Int,
        colorLabel: ColorLabel?,
        flag: PickFlag?,
        keywords: [String]
    ) throws -> AssetMetadata {
        guard Self.isValidRating(rating) else {
            throw TeststripError.invalidState(Self.invalidRatingMessage)
        }
        return AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords)
    }

    private static func isValidRating(_ rating: Int) -> Bool {
        validRatingRange.contains(rating)
    }
}

public struct AssetTechnicalMetadata: Codable, Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var isoSpeed: Int?
    public var aperture: Double?
    public var shutterSpeed: Double?
    public var focalLength: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var capturedAt: Date?
    public var provenance: ProviderProvenance

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        isoSpeed: Int? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        focalLength: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        capturedAt: Date? = nil,
        provenance: ProviderProvenance
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.isoSpeed = isoSpeed
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.focalLength = focalLength
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.capturedAt = capturedAt
        self.provenance = provenance
    }
}
