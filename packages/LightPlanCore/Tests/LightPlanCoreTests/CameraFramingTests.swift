import XCTest
@testable import LightPlanCore

final class CameraFramingTests: XCTestCase {
    private let radians = Double.pi / 180
    private let time = Date(timeIntervalSince1970: 1_789_617_600)

    func testFieldOfViewUsesFullFrameEquivalentAndPortraitSwapsDimensions() throws {
        let landscape = try CameraFraming(focalLength35mm: 50)
        let portrait = try CameraFraming(focalLength35mm: 50, orientation: .portrait)
        // Independent reference for a 50 mm lens on 36 × 24 mm at infinity.
        XCTAssertEqual(landscape.horizontalFieldOfViewDegrees, 39.597752709049864, accuracy: 1e-12)
        XCTAssertEqual(landscape.verticalFieldOfViewDegrees, 26.991466561591622, accuracy: 1e-12)
        XCTAssertEqual(landscape.frameAspectRatio, 1.5)
        XCTAssertEqual(portrait.frameAspectRatio, 2.0 / 3.0)
        XCTAssertEqual(portrait.horizontalFieldOfViewDegrees, landscape.verticalFieldOfViewDegrees)
        XCTAssertEqual(portrait.verticalFieldOfViewDegrees, landscape.horizontalFieldOfViewDegrees)
    }

    func testCenteredDiscUsesAngularDiameterRatherThanFixedMarkerSize() throws {
        for focalLength in [14.0, 50, 200, 1200] {
            let frame = try CameraFraming(focalLength35mm: focalLength)
            let result = try frame.project(bodyAzimuthDegrees: 90, bodyAltitudeDegrees: 0,
                                           angularDiameterDegrees: 0.5, cameraBearingDegrees: 90)
            XCTAssertEqual(result.bodyNormalizedCenter, FramePoint(x: 0.5, y: 0.5))
            let bounds = try XCTUnwrap(result.bodyBounds)
            XCTAssertEqual(bounds.width, 2 * focalLength * tan(0.25 * radians) / 36, accuracy: 1e-12)
            XCTAssertEqual(bounds.height, 2 * focalLength * tan(0.25 * radians) / 24, accuracy: 1e-12)
            XCTAssertEqual(result.visibility, .inFrame)
            XCTAssertEqual(result.bodyOutline.count, 96)
        }
    }

    func testNorthWrapAndLeftRightConventions() throws {
        let frame = try CameraFraming(focalLength35mm: 50)
        let right = try frame.project(bodyAzimuthDegrees: 1, bodyAltitudeDegrees: 0,
                                      angularDiameterDegrees: 0.5, cameraBearingDegrees: 359)
        let left = try frame.project(bodyAzimuthDegrees: 359, bodyAltitudeDegrees: 0,
                                     angularDiameterDegrees: 0.5, cameraBearingDegrees: 1)
        XCTAssertEqual(try XCTUnwrap(right.bodyNormalizedCenter).x, 0.5 + 50 * tan(2 * radians) / 36, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(left.bodyNormalizedCenter).x, 0.5 - 50 * tan(2 * radians) / 36, accuracy: 1e-12)
        let unwrapped = try frame.project(bodyAzimuthDegrees: 721, bodyAltitudeDegrees: 0,
                                          angularDiameterDegrees: 0.5, cameraBearingDegrees: -1)
        XCTAssertEqual(unwrapped.bodyNormalizedCenter, right.bodyNormalizedCenter)
    }

    func testHighPitchProjectsByCameraAxesAndPortraitRemainsLevel() throws {
        let frame = try CameraFraming(focalLength35mm: 50, referenceAltitudeDegrees: 60)
        let result = try frame.project(bodyAzimuthDegrees: 0, bodyAltitudeDegrees: 50,
                                       angularDiameterDegrees: 0.5, cameraBearingDegrees: 0)
        let center = try XCTUnwrap(result.bodyNormalizedCenter)
        XCTAssertEqual(center.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(center.y, 0.5 + 50 * tan(10 * radians) / 24, accuracy: 1e-12)
        let portrait = try CameraFraming(focalLength35mm: 50, orientation: .portrait, referenceAltitudeDegrees: 60)
            .project(bodyAzimuthDegrees: 0, bodyAltitudeDegrees: 50, angularDiameterDegrees: 0.5, cameraBearingDegrees: 0)
        XCTAssertEqual(try XCTUnwrap(portrait.bodyNormalizedCenter).y, 0.5 + 50 * tan(10 * radians) / 36, accuracy: 1e-12)
        let zenith = try CameraFraming(focalLength35mm: 14, referenceAltitudeDegrees: 60)
            .project(bodyAzimuthDegrees: 213, bodyAltitudeDegrees: 90, angularDiameterDegrees: 0.5, cameraBearingDegrees: 35)
        XCTAssertEqual(try XCTUnwrap(zenith.bodyNormalizedCenter).x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(zenith.visibility, .inFrame)
    }

    func testOffAxisDiscBoundsMatchIndependentTangentAngles() throws {
        let frame = try CameraFraming(focalLength35mm: 14)
        let result = try frame.project(bodyAzimuthDegrees: 45, bodyAltitudeDegrees: 0,
                                       angularDiameterDegrees: 0.6, cameraBearingDegrees: 0)
        let bounds = try XCTUnwrap(result.bodyBounds)
        XCTAssertEqual(bounds.minX, 0.5 + 14 * tan(44.7 * radians) / 36, accuracy: 1e-12)
        XCTAssertEqual(bounds.maxX, 0.5 + 14 * tan(45.3 * radians) / 36, accuracy: 1e-12)
        XCTAssertTrue(result.bodyOutline.allSatisfy {
            $0.x >= bounds.minX - 1e-12 && $0.x <= bounds.maxX + 1e-12 &&
            $0.y >= bounds.minY - 1e-12 && $0.y <= bounds.maxY + 1e-12
        })
    }

    func testTiltedCameraUsesSphericalGeometryAcrossLargeAzimuthChanges() throws {
        let frame = try CameraFraming(focalLength35mm: 14, referenceAltitudeDegrees: 60)
        let result = try frame.project(bodyAzimuthDegrees: 90, bodyAltitudeDegrees: 60,
                                       angularDiameterDegrees: 0.5, cameraBearingDegrees: 0)
        let center = try XCTUnwrap(result.bodyNormalizedCenter)
        // The true camera vector is (1/2, sqrt(3)/4, 3/4), although the yaw
        // separation is 90°. Treating that yaw as a flat image offset is invalid.
        XCTAssertEqual(center.x, 0.5 + 14 * (2.0 / 3.0) / 36, accuracy: 1e-12)
        XCTAssertEqual(center.y, 0.5 - 14 / (sqrt(3) * 24), accuracy: 1e-12)
        XCTAssertEqual(result.visibility, .inFrame)
        let rotated = try frame.project(bodyAzimuthDegrees: 220, bodyAltitudeDegrees: 60,
                                        angularDiameterDegrees: 0.5, cameraBearingDegrees: 130)
        XCTAssertEqual(rotated.bodyNormalizedCenter, result.bodyNormalizedCenter)
    }

    func testOffAxisOutlineHasConstantSphericalRadiusAfterInverseProjection() throws {
        let frame = try CameraFraming(focalLength35mm: 50, referenceAltitudeDegrees: 45)
        let result = try frame.project(bodyAzimuthDegrees: 42, bodyAltitudeDegrees: 49,
                                       angularDiameterDegrees: 0.6, cameraBearingDegrees: 30)
        let center = try XCTUnwrap(result.bodyNormalizedCenter)
        func ray(_ point: FramePoint) -> (Double, Double, Double) {
            let x = (point.x - 0.5) * 36 / 50, y = (0.5 - point.y) * 24 / 50
            let length = sqrt(x * x + y * y + 1)
            return (x / length, y / length, 1 / length)
        }
        let axis = ray(center)
        for point in result.bodyOutline {
            let edge = ray(point)
            let separation = acos(min(1, max(-1, axis.0 * edge.0 + axis.1 * edge.1 + axis.2 * edge.2))) / radians
            XCTAssertEqual(separation, 0.3, accuracy: 1e-9)
        }
    }

    func testFrameEdgeDistinguishesPartialOutsideAndBehind() throws {
        let frame = try CameraFraming(focalLength35mm: 50)
        let edge = frame.horizontalFieldOfViewDegrees / 2
        XCTAssertEqual(try frame.project(bodyAzimuthDegrees: edge + 0.1, bodyAltitudeDegrees: 0,
            angularDiameterDegrees: 0.5, cameraBearingDegrees: 0).visibility, .partiallyInFrame)
        XCTAssertEqual(try frame.project(bodyAzimuthDegrees: edge + 0.3, bodyAltitudeDegrees: 0,
            angularDiameterDegrees: 0.5, cameraBearingDegrees: 0).visibility, .outsideFrame)
        for azimuth in [90.0, 180, 270] {
            let result = try frame.project(bodyAzimuthDegrees: azimuth, bodyAltitudeDegrees: 0,
                angularDiameterDegrees: 0.5, cameraBearingDegrees: 0)
            XCTAssertEqual(result.visibility, .behindCamera)
            XCTAssertNil(result.bodyNormalizedCenter)
            XCTAssertNil(result.bodyBounds)
            XCTAssertTrue(result.bodyOutline.isEmpty)
        }
        let focalPlane = try frame.project(bodyAzimuthDegrees: 89.9, bodyAltitudeDegrees: 0,
            angularDiameterDegrees: 0.5, cameraBearingDegrees: 0)
        XCTAssertEqual(focalPlane.visibility, .outsideFrame)
        XCTAssertNil(focalPlane.bodyBounds)
        XCTAssertTrue(try XCTUnwrap(focalPlane.bodyNormalizedCenter).x.isFinite)
    }

    func testCornerBoundingBoxOverlapDoesNotClaimDiscInFrame() throws {
        let frame = try CameraFraming(focalLength35mm: 1200)
        // Disc center is 0.20° beyond each corner axis: its box touches both edges,
        // but its circular limb with radius 0.25° cannot reach the corner diagonally.
        let azimuth = frame.horizontalFieldOfViewDegrees / 2 + 0.2
        let altitude = frame.verticalFieldOfViewDegrees / 2 + 0.2
        let result = try frame.project(bodyAzimuthDegrees: azimuth, bodyAltitudeDegrees: altitude,
            angularDiameterDegrees: 0.5, cameraBearingDegrees: 0)
        let bounds = try XCTUnwrap(result.bodyBounds)
        XCTAssertLessThan(bounds.minX, 1)
        XCTAssertGreaterThan(bounds.maxY, 0)
        XCTAssertEqual(result.visibility, .outsideFrame)
    }

    func testInputsAndDecodedNonfiniteValuesAreRejected() throws {
        for focalLength in [Double.nan, .infinity, -.infinity, 0, 13.99, 1200.01] {
            XCTAssertThrowsError(try CameraFraming(focalLength35mm: focalLength))
        }
        for altitude in [Double.nan, .infinity, -30.01, 60.01] {
            XCTAssertThrowsError(try CameraFraming(referenceAltitudeDegrees: altitude))
        }
        let frame = try CameraFraming()
        XCTAssertThrowsError(try frame.project(bodyAzimuthDegrees: .nan, bodyAltitudeDegrees: 0, angularDiameterDegrees: 0.5, cameraBearingDegrees: 0))
        XCTAssertThrowsError(try frame.project(bodyAzimuthDegrees: 0, bodyAltitudeDegrees: 91, angularDiameterDegrees: 0.5, cameraBearingDegrees: 0))
        XCTAssertThrowsError(try frame.project(bodyAzimuthDegrees: 0, bodyAltitudeDegrees: 0, angularDiameterDegrees: -1, cameraBearingDegrees: 0))
        XCTAssertThrowsError(try frame.project(bodyAzimuthDegrees: 0, bodyAltitudeDegrees: 0, angularDiameterDegrees: 0.5, cameraBearingDegrees: .infinity))
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for json in [
            #"{"focalLength35mm":"NaN","orientation":"landscape","referenceAltitudeDegrees":0}"#,
            #"{"focalLength35mm":50,"orientation":"landscape","referenceAltitudeDegrees":"Infinity"}"#,
            #"{"focalLength35mm":50,"orientation":"square","referenceAltitudeDegrees":0}"#,
            #"{"focalLength35mm":50,"orientation":"landscape"}"#
        ] { XCTAssertThrowsError(try decoder.decode(CameraFraming.self, from: Data(json.utf8))) }
    }

    func testAngularDiametersVaryWithOrbitalDistanceAndObserver() throws {
        let coordinate = try Coordinate(latitude: 0, longitude: 0)
        let january = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-03T12:00:00Z"))
        let july = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-04T12:00:00Z"))
        let winterSun = try Astronomy.angularDiameter(.sun, at: january, coordinate: coordinate)
        let summerSun = try Astronomy.angularDiameter(.sun, at: july, coordinate: coordinate)
        XCTAssertTrue((0.54...0.55).contains(winterSun))
        XCTAssertTrue((0.52...0.53).contains(summerSun))
        XCTAssertGreaterThan(winterSun, summerSun)
        var moonSizes: [Double] = []
        for longitude in stride(from: -180.0, through: 180.0, by: 30) {
            let size = try Astronomy.angularDiameter(.moon, at: time, coordinate: Coordinate(latitude: 0, longitude: longitude))
            XCTAssertTrue((0.47...0.58).contains(size))
            moonSizes.append(size)
        }
        XCTAssertGreaterThan(try XCTUnwrap(moonSizes.max()) - XCTUnwrap(moonSizes.min()), 0.005)
        XCTAssertThrowsError(try Astronomy.angularDiameter(.moon, at: Date(timeIntervalSince1970: .nan), coordinate: coordinate))
        XCTAssertThrowsError(try Astronomy.angularDiameter(.sun, at: Date(timeIntervalSince1970: 10_000_000_000), coordinate: coordinate))
    }

    func testCameraSnapshotRoundTripAndLegacyCompositionDecode() throws {
        let subject = try VisualGeometry.destination(from: Place.example.coordinate, bearing: 250, meters: 900)
        let camera = try CameraFraming(focalLength35mm: 300, orientation: .portrait, referenceAltitudeDegrees: 12)
        let composition = try CompositionPlan(body: .moon, subject: subject, desiredOffsetDegrees: 10,
                                             instant: time, cameraFraming: camera)
        let plan = try ShootPlan(title: "Framed moon", place: .example, date: time, target: .composition,
                                 now: time, composition: composition)
        let restored = try Archive.decode(Archive(places: [], plans: [plan]).encoded())
        XCTAssertEqual(restored.plans.first?.composition?.cameraFraming, camera)
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(composition)) as? [String: Any])
        legacy.removeValue(forKey: "cameraFraming")
        XCTAssertNil(try decoder.decode(CompositionPlan.self, from: JSONSerialization.data(withJSONObject: legacy)).cameraFraming)
        legacy["cameraFraming"] = ["focalLength35mm": 0, "orientation": "landscape", "referenceAltitudeDegrees": 0]
        XCTAssertThrowsError(try decoder.decode(CompositionPlan.self, from: JSONSerialization.data(withJSONObject: legacy)))
        let projection = try camera.project(body: .moon, at: time, observer: Place.example.coordinate, subject: subject)
        XCTAssertEqual(projection.cameraBearingDegrees, 250, accuracy: 0.00001)
        XCTAssertThrowsError(try camera.project(body: .moon, at: time, observer: subject, subject: subject))
    }
}
