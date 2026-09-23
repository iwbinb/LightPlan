import Foundation
import Combine
@preconcurrency import CoreLocation
@preconcurrency import MapKit
import LightPlanCore

@MainActor final class PlaceSearch: ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var busy = false
    @Published var errorKey: String?
    @Published var unresolvedCoordinate: Coordinate?
    @Published var unresolvedName = ""
    private var request: MKLocalSearch?
    private var sequence = UUID()
    private var timeout: Task<Void, Never>?
    func cancel() {
        sequence = UUID(); request?.cancel(); request = nil; timeout?.cancel(); timeout = nil; busy = false
    }
    func search(_ query: String) async {
        cancel(); results = []; errorKey = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = UUID(); sequence = id; busy = true
        let spec = MKLocalSearch.Request(); spec.naturalLanguageQuery = String(trimmed.prefix(200))
        let task = MKLocalSearch(request: spec); request = task
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.sequence == id, self.busy else { return }
            self.request?.cancel(); self.busy = false; self.errorKey = "error.searchTimeout"
        }
        do {
            let response = try await task.start()
            guard id == sequence, !Task.isCancelled else { return }
            timeout?.cancel(); results = response.mapItems; busy = false
            if results.isEmpty { errorKey = "place.noResults" }
        } catch {
            if id == sequence { timeout?.cancel(); busy = false; if errorKey == nil { errorKey = "error.search" } }
        }
    }
    func resolve(_ item: MKMapItem) async throws -> Place {
        let coordinate = try Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
        let name = item.name ?? L10n.text("place.unnamed")
        let geocoder = CLGeocoder()
        let timer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { geocoder.cancelGeocode() }
        }
        defer { timer.cancel() }
        do {
            let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard let zone = marks.first?.timeZone else { throw LightPlanError.invalidTimeZone }
            return try Place(name: String(name.prefix(120)), coordinate: coordinate, timeZoneID: zone.identifier)
        } catch {
            unresolvedCoordinate = coordinate; unresolvedName = name
            throw LightPlanError.invalidTimeZone
        }
    }
}

/// Location only starts after an explicit user action. No launch-time permission request.
@MainActor final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var busy = false
    @Published var errorKey: String?
    @Published var fallbackCoordinate: Coordinate?
    @Published private(set) var currentCoordinate: Coordinate?
    var onPlace: ((Place) -> Void)?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var requested = false
    private var liveTracking = false
    private var requestID = UUID()
    private var timeout: Task<Void, Never>?
    override init() {
        super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func request() {
        guard !requested else { return }
        requestID = UUID(); fallbackCoordinate = nil; currentCoordinate = nil
        liveTracking = false; manager.stopUpdatingLocation()
        errorKey = nil; requested = true; busy = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: locate()
        default: requested = false; busy = false; errorKey = "error.location"
        }
    }
    func cancel() {
        requestID = UUID(); requested = false; liveTracking = false; busy = false
        currentCoordinate = nil
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation(); geocoder.cancelGeocode()
        onPlace = nil
    }
    /// Only the visible Map screen calls this after an explicit GPS action.
    /// `cancel()` stops updates when that screen disappears.
    func startLiveUpdates() {
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else { return }
        liveTracking = true
        manager.startUpdatingLocation()
    }
    private func locate() {
        busy = true; manager.requestLocation(); timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.busy else { return }
            self.manager.stopUpdatingLocation(); self.geocoder.cancelGeocode(); self.busy = false; self.requested = false; self.errorKey = "error.location"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requested else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: locate()
        case .denied, .restricted: requested = false; busy = false; errorKey = "error.location"
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard requested else {
            if liveTracking { currentCoordinate = nil }
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["LIGHTPLAN_VISUAL_FIXTURE"] == "1" {
            let failure = error as NSError
            UserDefaults.standard.set("\(failure.domain):\(failure.code)", forKey: "lightPlanDebugLocationFailure")
        }
        #endif
        busy = false; requested = false; timeout?.cancel(); errorKey = "error.location"
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requested || liveTracking else { return }
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 120 else {
            if requested {
                busy = false; requested = false; timeout?.cancel(); errorKey = "error.location"
            }
            return
        }
        if let coordinate = try? Coordinate(latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude) {
            currentCoordinate = coordinate
        }
        guard requested else { return }
        requested = false
        let id = requestID
        Task {
            defer { if id == requestID { busy = false; timeout?.cancel() } }
            do {
                let coordinate = try Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                guard id == requestID else { return }
                fallbackCoordinate = coordinate
                let marks = try await geocoder.reverseGeocodeLocation(location)
                guard id == requestID else { return }
                guard let zone = marks.first?.timeZone else { throw LightPlanError.invalidTimeZone }
                let name = marks.first?.locality ?? L10n.text("place.current")
                let place = try Place(name: String(name.prefix(120)), coordinate: coordinate, timeZoneID: zone.identifier)
                fallbackCoordinate = nil; onPlace?(place)
            } catch { if id == requestID { errorKey = "error.timezone" } }
        }
    }
}
