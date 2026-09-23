import Foundation

public enum FrameOrientation: String, Codable, CaseIterable, Hashable, Sendable {
    case landscape, portrait
}

public struct FramePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
}

public struct FrameBounds: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double
    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
}

public enum FrameVisibility: String, Sendable {
    case inFrame, partiallyInFrame, outsideFrame, behindCamera
}

public struct CameraFramingProjection: Sendable {
    /// Sensor coordinates, with (0, 0) at top left and (1, 1) at bottom right.
    /// Coordinates outside that range are intentional; nil means no forward projection.
    public let bodyNormalizedCenter: FramePoint?
    /// Axis-aligned bounds of the projected spherical limb, not a fixed-size UI marker.
    public let bodyBounds: FrameBounds?
    /// Geometric limb samples for a correctly oriented off-axis outline. Empty when
    /// the disc crosses the focal plane or is behind the camera. Clip to the frame.
    public let bodyOutline: [FramePoint]
    public let angularDiameterDegrees: Double
    public let cameraBearingDegrees: Double
    public let bodyAltitudeDegrees: Double
    public let visibility: FrameVisibility
}

/// A level-roll, rectilinear pinhole camera using a 36 × 24 mm equivalent sensor.
/// Camera yaw points from observer to subject; pitch is the user-supplied reference
/// point altitude. This is geometric framing, without terrain, refraction, lens
/// distortion, subject dimensions, focus breathing or camera calibration.
public struct CameraFraming: Codable, Equatable, Hashable, Sendable {
    public let focalLength35mm: Double
    public let orientation: FrameOrientation
    public let referenceAltitudeDegrees: Double

    public init(focalLength35mm: Double = 50, orientation: FrameOrientation = .landscape,
                referenceAltitudeDegrees: Double = 0) throws {
        guard focalLength35mm.isFinite, (14...1200).contains(focalLength35mm),
              referenceAltitudeDegrees.isFinite, (-30...60).contains(referenceAltitudeDegrees) else {
            throw LightPlanError.invalidNumber
        }
        self.focalLength35mm = focalLength35mm
        self.orientation = orientation
        self.referenceAltitudeDegrees = referenceAltitudeDegrees
    }

    private var sensorWidth: Double { orientation == .landscape ? 36 : 24 }
    private var sensorHeight: Double { orientation == .landscape ? 24 : 36 }
    public var frameAspectRatio: Double { sensorWidth / sensorHeight }
    /// AFOV = 2 atan(sensor dimension / (2 focal length)), with focus at infinity.
    /// Source: Edmund Optics, Understanding Focal Length and Field of View.
    public var horizontalFieldOfViewDegrees: Double { 2 * atan(sensorWidth / (2 * focalLength35mm)) * 180 / .pi }
    public var verticalFieldOfViewDegrees: Double { 2 * atan(sensorHeight / (2 * focalLength35mm)) * 180 / .pi }

    public func validated() throws -> Self {
        try Self(focalLength35mm: focalLength35mm, orientation: orientation,
                 referenceAltitudeDegrees: referenceAltitudeDegrees)
    }

    private enum CodingKeys: String, CodingKey { case focalLength35mm, orientation, referenceAltitudeDegrees }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(focalLength35mm: values.decode(Double.self, forKey: .focalLength35mm),
                      orientation: values.decode(FrameOrientation.self, forKey: .orientation),
                      referenceAltitudeDegrees: values.decode(Double.self, forKey: .referenceAltitudeDegrees))
    }

    public func project(body: CelestialBody, at instant: Date, observer: Coordinate,
                        subject: Coordinate) throws -> CameraFramingProjection {
        guard let bearing = Geometry.bearing(from: observer, to: subject) else {
            throw LightPlanError.invalidCoordinate
        }
        let position = try Astronomy.position(body, at: instant, coordinate: observer)
        return try project(bodyAzimuthDegrees: position.azimuth, bodyAltitudeDegrees: position.altitude,
                           angularDiameterDegrees: Astronomy.angularDiameter(body, at: instant, coordinate: observer),
                           cameraBearingDegrees: bearing)
    }

    /// Projects a spherical disc from a measured/calculated direction. Positive horizontal
    /// displacement goes right; increasing altitude goes up. Roll remains level in either
    /// orientation: portrait swaps sensor dimensions, not the physical horizon.
    public func project(bodyAzimuthDegrees: Double, bodyAltitudeDegrees: Double,
                        angularDiameterDegrees: Double, cameraBearingDegrees: Double) throws -> CameraFramingProjection {
        guard bodyAzimuthDegrees.isFinite, cameraBearingDegrees.isFinite,
              bodyAltitudeDegrees.isFinite, (-90...90).contains(bodyAltitudeDegrees),
              angularDiameterDegrees.isFinite, (0...2).contains(angularDiameterDegrees) else {
            throw LightPlanError.invalidNumber
        }
        let radians = Double.pi / 180
        let difference = (Astronomy.normalize(bodyAzimuthDegrees) - Astronomy.normalize(cameraBearingDegrees)) * radians
        let altitude = bodyAltitudeDegrees * radians, pitch = referenceAltitudeDegrees * radians
        // Dot the local sky unit vector into camera right/up/forward axes. Subtracting
        // angles alone would be wrong when the camera is tilted or near the zenith.
        let x = cos(altitude) * sin(difference)
        let y = sin(altitude) * cos(pitch) - cos(altitude) * cos(difference) * sin(pitch)
        let z = sin(altitude) * sin(pitch) + cos(altitude) * cos(difference) * cos(pitch)
        let halfWidth = sensorWidth / (2 * focalLength35mm)
        let halfHeight = sensorHeight / (2 * focalLength35mm)
        let radius = angularDiameterDegrees * radians / 2, sineRadius = sin(radius)

        var outline: [FramePoint] = []
        func result(_ center: FramePoint?, _ bounds: FrameBounds?, _ visibility: FrameVisibility) -> CameraFramingProjection {
            CameraFramingProjection(bodyNormalizedCenter: center, bodyBounds: bounds,
                bodyOutline: outline,
                angularDiameterDegrees: angularDiameterDegrees,
                cameraBearingDegrees: Astronomy.normalize(cameraBearingDegrees),
                bodyAltitudeDegrees: bodyAltitudeDegrees, visibility: visibility)
        }
        // A center in or behind the focal plane has no finite forward image. A disc
        // crossing the focal plane cannot intersect the bounded FOV supported here.
        guard z > 1e-12 else { return result(nil, nil, .behindCamera) }
        let center = FramePoint(x: 0.5 + x / z / (2 * halfWidth), y: 0.5 - y / z / (2 * halfHeight))
        guard z > sineRadius + 1e-12 else { return result(center, nil, .outsideFrame) }

        let tangentScale = hypot(x, z)
        let rightX = z / tangentScale, rightZ = -x / tangentScale
        let upX = -x * y / tangentScale, upY = tangentScale, upZ = -z * y / tangentScale
        outline = (0..<96).map { index in
            let angle = 2 * Double.pi * Double(index) / 96
            let lx = x * cos(radius) + sineRadius * (rightX * cos(angle) + upX * sin(angle))
            let ly = y * cos(radius) + sineRadius * upY * sin(angle)
            let lz = z * cos(radius) + sineRadius * (rightZ * cos(angle) + upZ * sin(angle))
            return FramePoint(x: 0.5 + lx / lz / (2 * halfWidth), y: 0.5 - ly / lz / (2 * halfHeight))
        }

        // Extremal slopes of the spherical limb are the tangent roots of its cone:
        // (z²-sin²r)t² - 2xz t + x²-sin²r = 0 (likewise for y).
        // This includes off-axis enlargement, which a constant diameter marker misses.
        let denominator = z * z - sineRadius * sineRadius
        func extent(_ component: Double) -> (Double, Double) {
            let span = sineRadius * sqrt(max(0, component * component + z * z - sineRadius * sineRadius))
            return ((component * z - span) / denominator, (component * z + span) / denominator)
        }
        let horizontal = extent(x), vertical = extent(y)
        let bounds = FrameBounds(minX: 0.5 + horizontal.0 / (2 * halfWidth),
                                 minY: 0.5 - vertical.1 / (2 * halfHeight),
                                 width: (horizontal.1 - horizontal.0) / (2 * halfWidth),
                                 height: (vertical.1 - vertical.0) / (2 * halfHeight))
        if bounds.minX >= 0, bounds.maxX <= 1, bounds.minY >= 0, bounds.maxY <= 1 {
            return result(center, bounds, .inFrame)
        }
        // Bounds overlap alone gives false positives at frame corners. Maximize the
        // dot product over the four frustum edges to test the actual spherical cap.
        if abs(x / z) <= halfWidth, abs(y / z) <= halfHeight {
            return result(center, bounds, .partiallyInFrame)
        }
        var maximumDot = -1.0
        func consider(_ horizontal: Double, _ vertical: Double) {
            let dot = (x * horizontal + y * vertical + z) / sqrt(1 + horizontal * horizontal + vertical * vertical)
            maximumDot = max(maximumDot, dot)
        }
        for edge in [-halfWidth, halfWidth] {
            consider(edge, -halfHeight); consider(edge, halfHeight)
            let base = x * edge + z
            if base > 0 { consider(edge, min(halfHeight, max(-halfHeight, y * (1 + edge * edge) / base))) }
        }
        for edge in [-halfHeight, halfHeight] {
            let base = y * edge + z
            if base > 0 { consider(min(halfWidth, max(-halfWidth, x * (1 + edge * edge) / base)), edge) }
        }
        return result(center, bounds, maximumDot >= cos(radius) - 1e-12 ? .partiallyInFrame : .outsideFrame)
    }
}
