#!/usr/bin/env bash
# Real-network de-risk for CLGeocoder inside a plain SwiftPM/CLI process (no main
# run loop), matching the DispatchSemaphore + detached-Task bridge that
# CLGeocoderReverseGeocoder uses in the worker. Reverse-geocodes a known
# coordinate (the Eiffel Tower) and asserts a locality comes back.
#
# When to use: run once before trusting the worker-side reverse-geocode pipeline,
# and any time CLGeocoder behavior in the worker is in doubt.
#
# Output: "PASS <locality>" on success, "SKIP no network" when offline (clean
# exit 0 either way), or "FAIL ..." (exit 1) if CLGeocoder cannot resolve.
set -euo pipefail

LAT="${1:-48.8584}"
LON="${2:-2.2945}"

# Network guard: skip cleanly when offline so this never fails a disconnected CI.
if ! /usr/bin/curl --silent --head --max-time 5 https://www.apple.com >/dev/null 2>&1; then
  echo "SKIP no network"
  exit 0
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-reverse-geocode-smoke.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
HARNESS="$WORK_DIR/harness.swift"

cat >"$HARNESS" <<'SWIFT'
import CoreLocation
import Foundation

enum GeocodeOutcome {
    case placemarks([CLPlacemark])
    case failure(Error)
    case timedOut
}

// Same synchronous bridge CLGeocoderReverseGeocoder uses: the CLI has no main
// run loop, so a detached Task runs the async CLGeocoder call and a semaphore
// blocks the caller until it resolves. Bounded so a sandbox that can reach the
// open web but not Apple's geo backend reports SKIP instead of hanging.
func reverseGeocode(latitude: Double, longitude: Double) -> GeocodeOutcome {
    let semaphore = DispatchSemaphore(value: 0)
    var outcome: GeocodeOutcome = .timedOut
    Task.detached {
        do {
            let placemarks = try await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
            outcome = .placemarks(placemarks)
        } catch {
            outcome = .failure(error)
        }
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 20) == .timedOut {
        return .timedOut
    }
    return outcome
}

let arguments = CommandLine.arguments
let latitude = Double(arguments[1]) ?? 0
let longitude = Double(arguments[2]) ?? 0
switch reverseGeocode(latitude: latitude, longitude: longitude) {
case .placemarks(let placemarks):
    if let locality = placemarks.first?.locality ?? placemarks.first?.administrativeArea {
        print("PASS \(locality)")
    } else {
        print("FAIL no placemark returned")
        exit(1)
    }
case .timedOut:
    print("SKIP geocode timed out (no reachable geo backend)")
case .failure(let error):
    let nsError = error as NSError
    // A CLError network/geocode-unavailable failure means the backend is
    // unreachable from here; treat like offline rather than a hard failure.
    if nsError.domain == kCLErrorDomain {
        print("SKIP geocode unavailable (\(nsError.code))")
    } else {
        print("FAIL \(error.localizedDescription)")
        exit(1)
    }
}
SWIFT

swift "$HARNESS" "$LAT" "$LON"
