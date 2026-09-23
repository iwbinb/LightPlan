import XCTest
@testable import LightPlanCore

final class OpportunityPersistenceTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_789_617_600)

    private func savedPlan(constraints: OpportunityConstraints?) throws -> ShootPlan {
        let subject = try VisualGeometry.destination(from: Place.example.coordinate, bearing: 250, meters: 900)
        let composition = try CompositionPlan(body: .moon, subject: subject, desiredOffsetDegrees: 10,
                                              instant: time, constraints: constraints)
        return try ShootPlan(title: "Constrained composition", place: .example, date: time,
                             target: .composition, now: time, composition: composition)
    }

    private func validObject() -> [String: Any] {
        ["maximumErrorDegrees": 3,
         "altitudeRange": ["lowerBound": 0, "upperBound": 15],
         "solarAltitudeRange": ["lowerBound": -6, "upperBound": 6]]
    }

    private func decode(_ object: [String: Any]) throws -> OpportunityConstraints {
        try JSONDecoder().decode(OpportunityConstraints.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testConstraintEncodingUsesStableExplicitBounds() throws {
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15,
                                                    solarAltitudeRange: -6...6)
        let data = try JSONEncoder().encode(constraints)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["maximumErrorDegrees", "altitudeRange", "solarAltitudeRange"])
        XCTAssertEqual(object["maximumErrorDegrees"] as? Double, 3)
        let altitude = try XCTUnwrap(object["altitudeRange"] as? [String: Double])
        XCTAssertEqual(altitude, ["lowerBound": 0, "upperBound": 15])
        let solar = try XCTUnwrap(object["solarAltitudeRange"] as? [String: Double])
        XCTAssertEqual(solar, ["lowerBound": -6, "upperBound": 6])
        XCTAssertEqual(try JSONDecoder().decode(OpportunityConstraints.self, from: data), constraints)
    }

    func testAbsentAndNullSolarRangeRemainUnrestricted() throws {
        var object = validObject()
        object.removeValue(forKey: "solarAltitudeRange")
        let missing = try decode(object)
        XCTAssertNil(missing.solarAltitudeRange)
        object["solarAltitudeRange"] = NSNull()
        XCTAssertEqual(try decode(object), missing)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(missing)) as? [String: Any])
        XCTAssertNil(output["solarAltitudeRange"])
    }

    func testCompositionArchiveRoundTripWithAndWithoutConditions() throws {
        let low = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15)
        let twilight = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...30,
                                                 solarAltitudeRange: -6...6)
        for constraints in [nil, low, twilight] as [OpportunityConstraints?] {
            let plan = try savedPlan(constraints: constraints)
            let decoded = try XCTUnwrap(Archive.decode(Archive(places: [], plans: [plan]).encoded()).plans.first)
            XCTAssertEqual(decoded, plan)
            XCTAssertEqual(decoded.composition?.constraints, constraints)
            let snapshot = try XCTUnwrap(decoded.composition)
            XCTAssertEqual(try snapshot.validated(observer: decoded.place, day: decoded.date), snapshot)
        }
    }

    func testOlderCompositionWithoutConstraintFieldStillDecodes() throws {
        let plan = try savedPlan(constraints: nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(try XCTUnwrap(plan.composition))) as? [String: Any])
        XCTAssertNil(object["constraints"], "Unconstrained plans must not require a new field")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(CompositionPlan.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.constraints)
        XCTAssertEqual(legacy.instant, plan.composition?.instant)
        object["constraints"] = NSNull()
        XCTAssertEqual(try decoder.decode(CompositionPlan.self, from: JSONSerialization.data(withJSONObject: object)), legacy)
    }

    func testReversedEmptyAndOutOfBoundsRangesThrowBeforeRangeConstruction() throws {
        for key in ["altitudeRange", "solarAltitudeRange"] {
            for bounds in [["lowerBound": 15, "upperBound": 0],
                           ["lowerBound": 5, "upperBound": 5],
                           ["lowerBound": -91, "upperBound": 0],
                           ["lowerBound": 0, "upperBound": 91]] {
                var object = validObject(); object[key] = bounds
                XCTAssertThrowsError(try decode(object), "Invalid \(key): \(bounds)")
            }
        }
    }

    func testNonFiniteValuesAreRejectedEvenWithPermissiveFloatDecoder() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for value in ["NaN", "Infinity", "-Infinity"] {
            var object = validObject(); object["maximumErrorDegrees"] = value
            XCTAssertThrowsError(try decoder.decode(OpportunityConstraints.self,
                from: JSONSerialization.data(withJSONObject: object)))
            for key in ["altitudeRange", "solarAltitudeRange"] {
                for bound in ["lowerBound", "upperBound"] {
                    object = validObject()
                    var bounds: [String: Any] = ["lowerBound": 0, "upperBound": 15]
                    bounds[bound] = value; object[key] = bounds
                    XCTAssertThrowsError(try decoder.decode(OpportunityConstraints.self,
                        from: JSONSerialization.data(withJSONObject: object)))
                }
            }
        }
    }

    func testRequiredConstraintFieldsAndTypesCannotSilentlyDefault() throws {
        for key in ["maximumErrorDegrees", "altitudeRange"] {
            var object = validObject(); object.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(object))
            object[key] = NSNull()
            XCTAssertThrowsError(try decode(object))
        }
        for error in [-1, 181] {
            var object = validObject(); object["maximumErrorDegrees"] = error
            XCTAssertThrowsError(try decode(object))
        }
        var object = validObject(); object["maximumErrorDegrees"] = "3"
        XCTAssertThrowsError(try decode(object))
        object = validObject(); object["altitudeRange"] = [0, 15]
        XCTAssertThrowsError(try decode(object))
        object = validObject(); object["solarAltitudeRange"] = ["lowerBound": -6]
        XCTAssertThrowsError(try decode(object))
    }

    func testInvalidNestedConditionsRejectTheWholeArchive() throws {
        let plan = try savedPlan(constraints: nil)
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Archive(places: [], plans: [plan]).encoded()) as? [String: Any])
        var plans = try XCTUnwrap(archive["plans"] as? [[String: Any]])
        var composition = try XCTUnwrap(plans[0]["composition"] as? [String: Any])
        var constraints = validObject()
        constraints["altitudeRange"] = ["lowerBound": 15, "upperBound": 0]
        composition["constraints"] = constraints
        plans[0]["composition"] = composition; archive["plans"] = plans
        XCTAssertThrowsError(try Archive.decode(JSONSerialization.data(withJSONObject: archive)))
    }

    func testImportedPlanKeepsItsSearchConditions() throws {
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15,
                                                    solarAltitudeRange: -6...6)
        let plan = try savedPlan(constraints: constraints)
        let preview = try ImportPreview(local: Archive(places: [], plans: []), incoming: Archive(places: [], plans: [plan]))
        let merged = try preview.merged(with: Archive(places: [], plans: []), policy: .keepLocal)
        XCTAssertEqual(merged.plans.first?.composition?.constraints, constraints)
        XCTAssertNil(merged.plans.first?.reminderLeadMinutes)
    }
}
