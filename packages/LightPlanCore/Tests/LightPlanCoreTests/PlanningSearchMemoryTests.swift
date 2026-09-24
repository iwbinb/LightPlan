import XCTest
@testable import LightPlanCore

final class PlanningSearchMemoryTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_789_617_600)
    private func context(_ body: CelestialBody = .sun, place: Place = .example, bearing: Double = 250) throws -> PlanningSearchContext {
        PlanningSearchContext(place: place,
            subject: try VisualGeometry.destination(from: place.coordinate, bearing: bearing, meters: 900),
            body: body, offset: 0)
    }
    private func defaults(_ date: Date? = nil) throws -> PlanningSearchConfiguration {
        PlanningSearchConfiguration(startDate: date ?? day, constraints: try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15))
    }

    func testCloseAndReopenRetainAppliedRangeFiltersAndOrder() throws {
        var memory = PlanningSearchMemory()
        let context = try context()
        let applied = PlanningSearchConfiguration(startDate: day.addingTimeInterval(3_600), days: 30,
            constraints: try OpportunityConstraints(solarAltitudeRange: -6...0), sortByDate: true)
        try memory.remember(applied, for: context, mapDate: day)
        XCTAssertEqual(try memory.configuration(for: context, mapDate: day, defaults: defaults()), applied)
    }

    func testAllIsAnExplicitChoiceNotMissingDefaults() throws {
        var memory = PlanningSearchMemory()
        let context = try context()
        let all = PlanningSearchConfiguration(startDate: day, days: 60, constraints: nil)
        try memory.remember(all, for: context, mapDate: day)
        let value = try memory.configuration(for: context, mapDate: day, defaults: defaults())
        XCTAssertEqual(value, all)
        XCTAssertNil(value.constraints)
    }

    func testSortingDoesNotChangeCalculationIdentity() throws {
        var a = try defaults(); let b = a
        a.sortByDate = true
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.calculationInput, b.calculationInput)
        a.days = 90
        XCTAssertNotEqual(a.calculationInput, b.calculationInput)
    }

    func testSunAndMoonHaveSeparateAppliedInputs() throws {
        var memory = PlanningSearchMemory()
        let sun = try context(.sun), moon = try context(.moon)
        let all = PlanningSearchConfiguration(startDate: day, days: 60, constraints: nil, sortByDate: true)
        let bright = PlanningSearchConfiguration(startDate: day, days: 30,
            constraints: try OpportunityConstraints(moonIlluminationRange: 0.8...1))
        try memory.remember(all, for: sun, mapDate: day)
        XCTAssertEqual(try memory.configuration(for: moon, mapDate: day, defaults: bright), bright)
        try memory.remember(bright, for: moon, mapDate: day)
        XCTAssertEqual(try memory.configuration(for: sun, mapDate: day, defaults: defaults()), all)
        XCTAssertEqual(try memory.configuration(for: moon, mapDate: day, defaults: defaults()), bright)
    }

    func testCancelledOptionDraftDoesNotModifyAppliedInputs() throws {
        var memory = PlanningSearchMemory()
        let context = try context(), applied = try defaults()
        try memory.remember(applied, for: context, mapDate: day)
        var draft = try memory.configuration(for: context, mapDate: day, defaults: defaults())
        draft.days = 90; draft.constraints = nil
        XCTAssertNotEqual(draft, applied)
        XCTAssertEqual(try memory.configuration(for: context, mapDate: day, defaults: defaults()), applied)
    }

    func testSelectingResultPreservesOriginalSearchRange() throws {
        var memory = PlanningSearchMemory()
        let context = try context(), original = try defaults()
        try memory.remember(original, for: context, mapDate: day)
        let selected = day.addingTimeInterval(5 * 86_400) // UTC fixture offset, not civil-day iteration.
        try memory.selectedResult(for: context, mapDate: selected)
        XCTAssertEqual(try memory.configuration(for: context, mapDate: selected, defaults: defaults(selected)), original)
    }

    func testExplicitNewMapDayReanchorsWithoutResettingFilters() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let place = try Place(name: "NY", coordinate: Coordinate(latitude: 40.7, longitude: -74), timeZoneID: zone.identifier)
        let before = try LocalDay.date(year: 2026, month: 3, day: 7, timeZone: zone)
        let after = try LocalDay.date(year: 2026, month: 3, day: 8, timeZone: zone)
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3_600)
        var memory = PlanningSearchMemory()
        let context = try context(.sun, place: place)
        var applied = PlanningSearchConfiguration(startDate: before, days: 30, constraints: nil, sortByDate: true)
        try memory.remember(applied, for: context, mapDate: before)
        applied.startDate = after
        XCTAssertEqual(try memory.configuration(for: context, mapDate: after, defaults: defaults(after)), applied)
    }

    func testNewSubjectReanchorsRangeButPreservesUserConditions() throws {
        var memory = PlanningSearchMemory()
        let a = try context(), b = try context(bearing: 90)
        var applied = PlanningSearchConfiguration(startDate: day.addingTimeInterval(7 * 86_400), days: 60, constraints: nil)
        try memory.remember(applied, for: a, mapDate: day)
        applied.startDate = day
        XCTAssertEqual(try memory.configuration(for: b, mapDate: day, defaults: defaults()), applied)
        // A late selection for another context cannot move the remembered map day.
        try memory.selectedResult(for: b, mapDate: day.addingTimeInterval(3_600))
        XCTAssertEqual(try memory.configuration(for: a, mapDate: day, defaults: defaults()).startDate,
                       day.addingTimeInterval(7 * 86_400))
    }

    func testRenameDoesNotResetSearchGeometry() throws {
        var renamed = Place.example; renamed.name = "Renamed"; renamed.id = UUID()
        XCTAssertEqual(try context(), try context(place: renamed))
    }

    func testTemplateResetOnlyReplacesSelectedBody() throws {
        var memory = PlanningSearchMemory()
        let sun = try context(.sun), moon = try context(.moon)
        let saved = PlanningSearchConfiguration(startDate: day, days: 60, constraints: nil)
        try memory.remember(saved, for: sun, mapDate: day)
        try memory.remember(saved, for: moon, mapDate: day)
        memory.reset(body: .moon)
        XCTAssertEqual(try memory.configuration(for: moon, mapDate: day, defaults: defaults()), try defaults())
        XCTAssertEqual(try memory.configuration(for: sun, mapDate: day, defaults: defaults()), saved)
    }

    func testInvalidInputsCannotReplacePreviousConfiguration() throws {
        var memory = PlanningSearchMemory()
        let context = try context(), original = try defaults()
        try memory.remember(original, for: context, mapDate: day)
        for count in [0, -1, 91] {
            var value = original; value.days = count
            XCTAssertThrowsError(try memory.remember(value, for: context, mapDate: day))
        }
        var value = original; value.startDate = Date(timeIntervalSince1970: .nan)
        XCTAssertThrowsError(try memory.remember(value, for: context, mapDate: day))
        XCTAssertEqual(try memory.configuration(for: context, mapDate: day, defaults: defaults()), original)
    }

    func testCoincidentSubjectAndInvalidOffsetAreRejected() throws {
        let memory = PlanningSearchMemory(), valid = try context()
        let same = PlanningSearchContext(place: .example, subject: Place.example.coordinate, body: .sun, offset: 0)
        let invalid = PlanningSearchContext(place: .example, subject: valid.subject, body: .sun, offset: .infinity)
        XCTAssertThrowsError(try memory.configuration(for: same, mapDate: day, defaults: defaults()))
        XCTAssertThrowsError(try memory.configuration(for: invalid, mapDate: day, defaults: defaults()))
    }
}
