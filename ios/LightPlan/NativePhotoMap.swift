import SwiftUI
@preconcurrency import MapKit
import LightPlanCore

/// Owns the actual MapKit view, so a map-style selection changes the tile provider
/// rather than only changing SwiftUI's description of a retained map.
struct NativePhotoMap: UIViewRepresentable {
    let place: Place
    @Binding var region: MKCoordinateRegion?
    let selectedBody: CelestialBody
    let satellite: Bool
    let compositionMode: Bool
    let tracks: [[CLLocationCoordinate2D]]
    let goldenSector: [CLLocationCoordinate2D]
    let summary: DaySummary?
    let sky: SkyPosition?
    let subject: Coordinate?
    let suggestedObserver: Coordinate?
    let deviceLocation: Coordinate?
    let language: String
    let onSubjectTap: (Coordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.accessibilityLabel = L10n.text("map.accessibility")
        map.accessibilityIdentifier = "map-canvas"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapMap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.update(map, from: self)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, from: self)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private var parent: NativePhotoMap
        private var currentStyle: Bool?
        private var commandedRegion: MKCoordinateRegion?
        private var staticKey = ""
        private var dynamicKey = ""
        private var staticOverlays: [MKOverlay] = []
        private var dynamicOverlays: [MKOverlay] = []
        private var overlayRoles: [ObjectIdentifier: OverlayRole] = [:]
        private var markers: [String: PhotoMarker] = [:]

        init(_ parent: NativePhotoMap) { self.parent = parent }

        func update(_ map: MKMapView, from value: NativePhotoMap) {
            parent = value
            if currentStyle != value.satellite {
                map.preferredConfiguration = value.satellite
                    ? MKImageryMapConfiguration(elevationStyle: .flat)
                    : MKStandardMapConfiguration(elevationStyle: .flat)
                // Some physical tile providers retained the old imagery despite a
                // preferredConfiguration update. Apply the public legacy selector too.
                map.mapType = value.satellite ? .satellite : .standard
                currentStyle = value.satellite
            }
            map.accessibilityValue = L10n.text(
                map.mapType == .standard ? "map.standard" : "map.satellite",
                language: value.language
            )
            let desired = value.region ?? MKCoordinateRegion(
                center: Self.cl(value.place.coordinate), latitudinalMeters: 3_500, longitudinalMeters: 3_500)
            if commandedRegion == nil || !Self.sameRegion(commandedRegion!, desired) {
                commandedRegion = desired
                map.setRegion(desired, animated: false)
            }
            updateStaticOverlays(map)
            updateDynamicOverlays(map)
            updateMarkers(map)
        }

        @objc func tapMap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView,
                  parent.compositionMode else { return }
            let point = gesture.location(in: map)
            let raw = map.convert(point, toCoordinateFrom: map)
            if let coordinate = try? Coordinate(latitude: raw.latitude, longitude: raw.longitude) {
                parent.onSubjectTap(coordinate)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            parent.compositionMode
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let actual = mapView.region
            commandedRegion = actual
            if parent.region.map({ !Self.sameRegion($0, actual) }) ?? true {
                Task { @MainActor [weak self] in self?.parent.region = actual }
            }
            for marker in markers.values where marker.kind == .rise || marker.kind == .set {
                (mapView.view(for: marker) as? PhotoMarkerView)?.positionEvent(in: mapView)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let role = overlayRoles[ObjectIdentifier(overlay as AnyObject)] ?? .track
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor(LPTheme.gold).withAlphaComponent(0.17)
                renderer.strokeColor = .clear
                return renderer
            }
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineWidth = role == .current ? 3 : role == .suggested ? 2.5 : role == .subject ? 2 : 1.5
            renderer.strokeColor = switch role {
            case .rise: UIColor(LPTheme.gold).withAlphaComponent(0.65)
            case .set: UIColor(LPTheme.sunset).withAlphaComponent(0.75)
            case .current: UIColor(parent.selectedBody == .sun ? LPTheme.gold : LPTheme.blue)
            case .subject: .white
            case .suggested: .systemGreen
            case .track: UIColor(parent.selectedBody == .sun ? LPTheme.gold : LPTheme.blue).withAlphaComponent(0.75)
            case .golden: UIColor(LPTheme.gold)
            }
            renderer.lineDashPattern = switch role {
            case .track: [3, 5]
            case .subject: [7, 5]
            case .suggested: [4, 4]
            case .current where (parent.sky?.altitude ?? 0) < 0: [7, 5]
            default: nil
            }
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let marker = annotation as? PhotoMarker else { return nil }
            let view = PhotoMarkerView(annotation: marker, reuseIdentifier: marker.kind.rawValue)
            view.configure(marker, in: mapView, body: parent.selectedBody)
            return view
        }

        private func updateStaticOverlays(_ map: MKMapView) {
            let key = "\(parent.place.id):\(parent.summary?.start.timeIntervalSince1970 ?? 0):\(parent.selectedBody.rawValue):\(parent.tracks.count):\(parent.tracks.reduce(0) { $0 + $1.count }):\(parent.goldenSector.count)"
            guard staticKey != key else { return }
            remove(staticOverlays, from: map)
            staticOverlays = []
            if parent.selectedBody == .sun, parent.goldenSector.count >= 3 {
                let polygon = MKPolygon(coordinates: parent.goldenSector, count: parent.goldenSector.count)
                add(polygon, role: .golden, to: map, list: &staticOverlays)
            }
            for segment in parent.tracks where segment.count >= 2 {
                let line = MKPolyline(coordinates: segment, count: segment.count)
                add(line, role: .track, to: map, list: &staticOverlays)
            }
            staticKey = key
        }

        private func updateDynamicOverlays(_ map: MKMapView) {
            let key = "\(parent.place.coordinate):\(parent.selectedBody.rawValue):\(parent.sky?.azimuth ?? -1):\(parent.sky?.altitude ?? -100):\(String(describing: parent.subject)):\(String(describing: parent.suggestedObserver)):\(parent.summary?.start.timeIntervalSince1970 ?? 0)"
            guard dynamicKey != key else { return }
            remove(dynamicOverlays, from: map)
            dynamicOverlays = []
            let origin = Self.cl(parent.place.coordinate)
            if let rise = parent.summary?.first(parent.selectedBody == .sun ? .sunrise : .moonrise),
               let end = endpoint(rise.azimuth) {
                let line = MKPolyline(coordinates: [origin, end], count: 2)
                add(line, role: .rise, to: map, list: &dynamicOverlays)
            }
            if let set = parent.summary?.first(parent.selectedBody == .sun ? .sunset : .moonset),
               let end = endpoint(set.azimuth) {
                let line = MKPolyline(coordinates: [origin, end], count: 2)
                add(line, role: .set, to: map, list: &dynamicOverlays)
            }
            if let sky = parent.sky, let end = endpoint(sky.azimuth) {
                let line = MKPolyline(coordinates: [origin, end], count: 2)
                add(line, role: .current, to: map, list: &dynamicOverlays)
            }
            if let subject = parent.subject {
                let line = MKPolyline(coordinates: [origin, Self.cl(subject)], count: 2)
                add(line, role: .subject, to: map, list: &dynamicOverlays)
            }
            if let subject = parent.subject, let suggested = parent.suggestedObserver {
                let line = MKPolyline(coordinates: [Self.cl(suggested), Self.cl(subject)], count: 2)
                add(line, role: .suggested, to: map, list: &dynamicOverlays)
            }
            dynamicKey = key
        }

        private func updateMarkers(_ map: MKMapView) {
            var specs: [(String, PinKind, CLLocationCoordinate2D, String, String)] = []
            specs.append(("observer", .observer, Self.cl(parent.place.coordinate), parent.place.name, ""))
            if let device = parent.deviceLocation {
                specs.append(("device", .device, Self.cl(device),
                              L10n.text("place.current", language: parent.language), ""))
            }
            let zone = parent.place.timeZone
            if let rise = parent.summary?.first(parent.selectedBody == .sun ? .sunrise : .moonrise),
               let end = endpoint(rise.azimuth) {
                specs.append(("rise", .rise, end, L10n.text(rise.kind.key, language: parent.language), L10n.time(rise.date, zone: zone)))
            }
            if let set = parent.summary?.first(parent.selectedBody == .sun ? .sunset : .moonset),
               let end = endpoint(set.azimuth) {
                specs.append(("set", .set, end, L10n.text(set.kind.key, language: parent.language), L10n.time(set.date, zone: zone)))
            }
            if let sky = parent.sky, let end = endpoint(sky.azimuth) {
                specs.append(("body", .body, end, L10n.text("body." + parent.selectedBody.rawValue, language: parent.language), ""))
            }
            if let subject = parent.subject {
                specs.append(("subject", .subject, Self.cl(subject),
                              L10n.text("composition.subject", language: parent.language), ""))
            }
            if let suggested = parent.suggestedObserver, parent.subject != nil {
                specs.append(("suggested", .suggested, Self.cl(suggested),
                              L10n.text("composition.suggestedStand", language: parent.language), ""))
            }
            let wanted = Set(specs.map(\.0))
            for id in markers.keys.filter({ !wanted.contains($0) }) {
                if let marker = markers.removeValue(forKey: id) { map.removeAnnotation(marker) }
            }
            for (id, kind, coordinate, title, subtitle) in specs {
                if let marker = markers[id] {
                    if abs(marker.coordinate.latitude - coordinate.latitude) > 1e-9 ||
                       abs(marker.coordinate.longitude - coordinate.longitude) > 1e-9 {
                        marker.coordinate = coordinate
                    }
                    if marker.title != title || marker.subtitle != subtitle {
                        marker.title = title; marker.subtitle = subtitle
                    }
                    (map.view(for: marker) as? PhotoMarkerView)?.configure(marker, in: map, body: parent.selectedBody)
                } else {
                    let marker = PhotoMarker(id: id, kind: kind, coordinate: coordinate, title: title, subtitle: subtitle)
                    markers[id] = marker
                    map.addAnnotation(marker)
                }
            }
        }

        private func endpoint(_ bearing: Double) -> CLLocationCoordinate2D? {
            (try? VisualGeometry.destination(from: parent.place.coordinate, bearing: bearing, meters: 1_050)).map(Self.cl)
        }

        private func remove(_ values: [MKOverlay], from map: MKMapView) {
            map.removeOverlays(values)
            for value in values { overlayRoles.removeValue(forKey: ObjectIdentifier(value as AnyObject)) }
        }

        private func add(_ overlay: MKOverlay, role: OverlayRole, to map: MKMapView,
                         list: inout [MKOverlay]) {
            overlayRoles[ObjectIdentifier(overlay as AnyObject)] = role
            list.append(overlay)
            map.addOverlay(overlay)
        }

        private static func cl(_ value: Coordinate) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
        }

        private static func sameRegion(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
            abs(a.center.latitude - b.center.latitude) < 1e-6 &&
            abs(a.center.longitude - b.center.longitude) < 1e-6 &&
            abs(a.span.latitudeDelta - b.span.latitudeDelta) < 1e-6 &&
            abs(a.span.longitudeDelta - b.span.longitudeDelta) < 1e-6
        }
    }
}

private enum OverlayRole { case golden, track, rise, set, current, subject, suggested }
private enum PinKind: String { case observer, device, rise, set, body, subject, suggested }

private final class PhotoMarker: MKPointAnnotation {
    let id: String
    let kind: PinKind
    init(id: String, kind: PinKind, coordinate: CLLocationCoordinate2D,
         title: String, subtitle: String) {
        self.id = id; self.kind = kind
        super.init()
        self.coordinate = coordinate; self.title = title; self.subtitle = subtitle
    }
}

private final class PhotoMarkerView: MKAnnotationView {
    private var rendered = ""
    private var eventSize: CGSize = .zero

    func configure(_ marker: PhotoMarker, in map: MKMapView, body: CelestialBody) {
        let signature = "\(marker.kind.rawValue):\(marker.title ?? ""):\(marker.subtitle ?? ""):\(body.rawValue)"
        if signature == rendered {
            if marker.kind == .rise || marker.kind == .set { positionEvent(in: map) }
            return
        }
        rendered = signature
        subviews.forEach { $0.removeFromSuperview() }
        canShowCallout = false
        switch marker.kind {
        case .rise, .set: makeEvent(marker, map: map)
        case .observer: makeSymbol("camera.fill", color: UIColor(LPTheme.accent),
                                   label: marker.title, anchorAtBottom: true, offsetAboveCoordinate: 12)
        case .device: makeDeviceLocation(marker)
        case .body: makeSymbol(body == .sun ? "sun.max.fill" : "moon.fill",
                               color: UIColor(LPTheme.ink).withAlphaComponent(0.85),
                               iconTint: UIColor(body == .sun ? LPTheme.gold : LPTheme.blue),
                               label: marker.title, anchorAtBottom: false)
        case .subject:
            makeSymbol("scope", color: .systemPurple, label: nil, anchorAtBottom: true)
            accessibilityLabel = marker.title
        case .suggested: makeSymbol("camera.fill", color: .systemGreen,
                                    iconTint: UIColor(LPTheme.ink), label: nil, anchorAtBottom: true)
            accessibilityLabel = marker.title
        }
    }

    func positionEvent(in map: MKMapView) {
        guard let marker = annotation as? PhotoMarker else { return }
        let point = map.convert(marker.coordinate, toPointTo: map)
        centerOffset = CGPoint(x: point.x >= map.bounds.midX ? -eventSize.width / 2 : eventSize.width / 2,
                               y: -eventSize.height / 2)
    }

    private func makeEvent(_ marker: PhotoMarker, map: MKMapView) {
        let title = UILabel()
        title.text = marker.title
        title.font = .preferredFont(forTextStyle: .caption2)
        title.numberOfLines = 0
        let time = UILabel()
        time.text = marker.subtitle
        time.font = .preferredFont(forTextStyle: .caption1).bold()
        time.numberOfLines = 1
        let width = min(max(86, max(title.intrinsicContentSize.width, time.intrinsicContentSize.width) + 16),
                        max(120, map.bounds.width * 0.38))
        let titleSize = title.sizeThatFits(CGSize(width: width - 16, height: .greatestFiniteMagnitude))
        let timeSize = time.sizeThatFits(CGSize(width: width - 16, height: .greatestFiniteMagnitude))
        let height = titleSize.height + timeSize.height + 20
        let badge = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        badge.backgroundColor = marker.kind == .rise ? UIColor(LPTheme.gold) : UIColor(LPTheme.sunset)
        badge.layer.cornerRadius = 11
        badge.layer.shadowColor = UIColor.black.cgColor
        badge.layer.shadowOpacity = 0.16
        badge.layer.shadowRadius = 5
        badge.layer.shadowOffset = CGSize(width: 0, height: 3)
        title.frame = CGRect(x: 8, y: 8, width: width - 16, height: titleSize.height)
        time.frame = CGRect(x: 8, y: title.frame.maxY + 3, width: width - 16, height: timeSize.height)
        title.textColor = UIColor(LPTheme.ink); time.textColor = UIColor(LPTheme.ink)
        badge.addSubview(title); badge.addSubview(time)
        bounds = badge.bounds; addSubview(badge)
        eventSize = badge.bounds.size
        positionEvent(in: map)
        accessibilityLabel = [marker.title, marker.subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    private func makeSymbol(_ name: String, color: UIColor, iconTint: UIColor = .white,
                            label: String?, anchorAtBottom: Bool,
                            offsetAboveCoordinate: CGFloat = 0) {
        let diameter: CGFloat = name == "sun.max.fill" || name == "moon.fill" ? 48 : 34
        let icon = UIImageView(image: UIImage(systemName: name,
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.48,
                                                                                 weight: .semibold)))
        icon.contentMode = .center
        icon.tintColor = iconTint
        icon.backgroundColor = color
        icon.layer.cornerRadius = diameter / 2
        icon.layer.borderWidth = 2
        icon.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.textColor = .white
        nameLabel.font = .preferredFont(forTextStyle: .caption1).bold()
        nameLabel.shadowColor = UIColor.black.withAlphaComponent(0.8)
        nameLabel.shadowOffset = CGSize(width: 0, height: 1)
        nameLabel.textAlignment = .center
        let labelWidth = label == nil ? 0 : min(230, nameLabel.intrinsicContentSize.width + 12)
        let width = max(diameter, labelWidth)
        let labelHeight = label == nil ? 0 : nameLabel.intrinsicContentSize.height + 3
        let height = diameter + labelHeight
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if anchorAtBottom {
            if label != nil {
                nameLabel.frame = CGRect(x: 0, y: 0, width: width, height: labelHeight)
                addSubview(nameLabel)
            }
            icon.frame = CGRect(x: (width - diameter) / 2, y: labelHeight, width: diameter, height: diameter)
            centerOffset = CGPoint(x: 0, y: -height / 2 - offsetAboveCoordinate)
        } else {
            icon.frame = CGRect(x: (width - diameter) / 2, y: 0, width: diameter, height: diameter)
            if label != nil {
                nameLabel.frame = CGRect(x: 0, y: diameter, width: width, height: labelHeight)
                addSubview(nameLabel)
            }
            centerOffset = CGPoint(x: 0, y: height / 2)
        }
        addSubview(icon)
        accessibilityLabel = label
    }

    private func makeDeviceLocation(_ marker: PhotoMarker) {
        let size: CGFloat = 34
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        let halo = UIView(frame: bounds)
        halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.19)
        halo.layer.cornerRadius = size / 2
        let dot = UIView(frame: CGRect(x: 9, y: 9, width: 16, height: 16))
        dot.backgroundColor = .systemBlue
        dot.layer.cornerRadius = 8
        dot.layer.borderWidth = 2
        dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.22
        dot.layer.shadowRadius = 3
        halo.addSubview(dot)
        addSubview(halo)
        isAccessibilityElement = true
        accessibilityLabel = marker.title
        accessibilityIdentifier = "map-user-location-dot"
    }
}

private extension UIFont {
    func bold() -> UIFont { .systemFont(ofSize: pointSize, weight: .semibold) }
}
