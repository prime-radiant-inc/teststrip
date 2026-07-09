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

    private static let validRatingRange = 0...5
    private static let invalidRatingMessage = "rating must be between 0 and 5"

    /// True once the user has set any portable field that mirrors to an XMP
    /// sidecar. A sidecar is written only after such a set (non-destructive), so
    /// this doubles as "a sidecar exists for this asset" — used to show a
    /// positive "Saved to sidecar" confirmation when nothing is pending.
    public var hasWrittenPortableMetadata: Bool {
        rating > 0
            || flag != nil
            || colorLabel != nil
            || !keywords.isEmpty
            || !(caption ?? "").isEmpty
            || !(creator ?? "").isEmpty
            || !(copyright ?? "").isEmpty
    }

    public init(
        rating: Int = 0,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        caption: String? = nil,
        creator: String? = nil,
        copyright: String? = nil
    ) {
        precondition(Self.isValidRating(rating), Self.invalidRatingMessage)

        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
        self.keywords = keywords
        self.caption = caption
        self.creator = creator
        self.copyright = copyright
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
