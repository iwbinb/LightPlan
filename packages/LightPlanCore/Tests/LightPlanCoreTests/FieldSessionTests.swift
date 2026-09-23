import XCTest
@testable import LightPlanCore

final class FieldSessionTests: XCTestCase {
    private let shoot = Date(timeIntervalSince1970: 1_789_617_600)

    func testCountdownMovesFromArrivalToShotThenNeverBecomesNegative() throws {
        let arrival = shoot.addingTimeInterval(-1800)
        let before = try FieldSessionStatus(arriveAt: arrival, shootAt: shoot, completedAt: nil, now: arrival.addingTimeInterval(-1.2))
        XCTAssertEqual(before.phase, .beforeArrival)
        XCTAssertEqual(before.secondsRemaining, 2)
        let preparing = try FieldSessionStatus(arriveAt: arrival, shootAt: shoot, completedAt: nil, now: arrival)
        XCTAssertEqual(preparing.phase, .preparing)
        XCTAssertEqual(preparing.secondsRemaining, 1800)
        for elapsed in [0.0, 59.9] {
            let atShot = try FieldSessionStatus(arriveAt: arrival, shootAt: shoot, completedAt: nil, now: shoot.addingTimeInterval(elapsed))
            XCTAssertEqual(atShot.phase, .shooting)
            XCTAssertNil(atShot.secondsRemaining)
        }
        let passed = try FieldSessionStatus(arriveAt: arrival, shootAt: shoot, completedAt: nil, now: shoot.addingTimeInterval(60))
        XCTAssertEqual(passed.phase, .passed)
        XCTAssertNil(passed.secondsRemaining)
    }

    func testCompletedStatusWinsBeforeOrAfterScheduledMoment() throws {
        for now in [shoot.addingTimeInterval(-3600), shoot.addingTimeInterval(3600)] {
            let value = try FieldSessionStatus(arriveAt: shoot, shootAt: shoot, completedAt: shoot, now: now)
            XCTAssertEqual(value.phase, .completed)
            XCTAssertNil(value.secondsRemaining)
        }
    }

    func testRepeatedDestinationHourUsesAbsoluteInstants() throws {
        let formatter = ISO8601DateFormatter()
        let beforeFallback = try XCTUnwrap(formatter.date(from: "2026-11-01T01:15:00-04:00"))
        let afterFallback = try XCTUnwrap(formatter.date(from: "2026-11-01T01:15:00-05:00"))
        let value = try FieldSessionStatus(arriveAt: afterFallback, shootAt: afterFallback, completedAt: nil, now: beforeFallback)
        XCTAssertEqual(value.secondsRemaining, 3600)
        XCTAssertEqual(value.phase, .beforeArrival)
    }

    func testInvalidScheduleAndNonFiniteTimesAreRejected() throws {
        XCTAssertThrowsError(try FieldSessionStatus(arriveAt: shoot.addingTimeInterval(1), shootAt: shoot, completedAt: nil, now: shoot))
        XCTAssertThrowsError(try FieldSessionStatus(arriveAt: shoot, shootAt: shoot, completedAt: nil, now: Date(timeIntervalSince1970: .nan)))
    }
}
