import CoreLocation
import Foundation

/// The place components a reverse-geocode lookup yields for a coordinate. All
/// optional: a lookup may resolve only a country, or nothing at all.
public struct ReverseGeocodeResult: Equatable, Sendable {
    public var locality: String?
    public var administrativeArea: String?
    public var country: String?

    public init(locality: String? = nil, administrativeArea: String? = nil, country: String? = nil) {
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.country = country
    }
}

/// Turns a coordinate into a place name. The reverse-geocode cache is keyed by
/// rounded coordinate behind this protocol so an offline dataset can slot in
/// later without touching the queue, the writer, or the schema.
///
/// A `nil` return means "no place found" (cache it so the coordinate is not
/// retried forever); a thrown error means a transient/rate-limited failure the
/// caller should re-queue and retry.
public protocol ReverseGeocoder: Sendable {
    func reverseGeocode(latitude: Double, longitude: Double) throws -> ReverseGeocodeResult?
}

/// Stock CoreLocation reverse geocoder. Bridges the async `CLGeocoder` API to the
/// synchronous protocol via a detached `Task` + `DispatchSemaphore`, because the
/// worker CLI has no main run loop. De-risked by
/// `script/verify_reverse_geocode_smoke.sh`.
public struct CLGeocoderReverseGeocoder: ReverseGeocoder {
    /// Comfortably under the worker supervisor's 120s command timeout: a hung
    /// CLGeocoder lookup must fail here, inside the per-item batch loop, so
    /// `recordGeocodeFailure` runs and attempt_count/last_attempted_at advance
    /// (feeding the existing backoff/terminal logic) — instead of the
    /// supervisor killing the whole worker with the queue row untouched, which
    /// left it redispatched forever.
    public static let defaultTimeout: TimeInterval = 30

    private let timeout: TimeInterval
    private let lookup: @Sendable (Double, Double) async throws -> ReverseGeocodeResult?

    public init(timeout: TimeInterval = Self.defaultTimeout) {
        self.init(timeout: timeout) { latitude, longitude in
            let placemarks = try await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
            return placemarks.first.map(Self.result(from:)) ?? nil
        }
    }

    /// Testing seam: `lookup` stands in for the CLGeocoder call so the
    /// timeout path can be exercised with a hanging fake.
    init(timeout: TimeInterval, lookup: @escaping @Sendable (Double, Double) async throws -> ReverseGeocodeResult?) {
        self.timeout = timeout
        self.lookup = lookup
    }

    public func reverseGeocode(latitude: Double, longitude: Double) throws -> ReverseGeocodeResult? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ReverseGeocodePlacemarkBox()
        let lookup = self.lookup
        let task = Task.detached {
            do {
                box.store(.success(try await lookup(latitude, longitude)))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            throw TeststripError.io("reverse geocode timed out after \(Int(timeout))s")
        }
        guard let outcome = box.load() else {
            throw TeststripError.io("reverse geocode returned no result")
        }
        return try outcome.get()
    }

    private static func result(from placemark: CLPlacemark) -> ReverseGeocodeResult? {
        let result = ReverseGeocodeResult(
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country
        )
        if result.locality == nil, result.administrativeArea == nil, result.country == nil {
            return nil
        }
        return result
    }
}

private final class ReverseGeocodePlacemarkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<ReverseGeocodeResult?, Error>?

    func store(_ result: Result<ReverseGeocodeResult?, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<ReverseGeocodeResult?, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
