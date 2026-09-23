import XCTest
@testable import LightPlanCore

final class SearchSamplingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func samples(peak: Double, maximum: Bool = true, duration: Double = 1_210,
                         step: Double = 300) throws -> [SearchSampling.Sample] {
        try SearchSampling.samples(in: DateInterval(start: start, duration: duration), step: step,
            tolerance: 0.0001, iterations: 48) {
                let square = pow($0.timeIntervalSince(self.start) - peak, 2)
                return maximum ? -square : square
            }
    }

    func testFirstCellPeakIsNotLost() throws {
        let values = try samples(peak: 1.25)
        XCTAssertGreaterThan(try XCTUnwrap(values.map(\.value).max()), -0.000001)
    }

    func testLastPartialCellPeakIsNotLost() throws {
        let values = try samples(peak: 1_208.75)
        let best = try XCTUnwrap(values.max { $0.value < $1.value })
        XCTAssertEqual(best.date.timeIntervalSince(start), 1_208.75, accuracy: 0.0001)
    }

    func testInteriorPeakIsRefined() throws {
        let values = try samples(peak: 450.25)
        XCTAssertGreaterThan(try XCTUnwrap(values.map(\.value).max()), -0.000001)
    }

    func testMinimaAtBothEdgesAndInsideAreRefined() throws {
        for minimum in [1.25, 450.25, 1_208.75] {
            let values = try samples(peak: minimum, maximum: false)
            XCTAssertLessThan(try XCTUnwrap(values.map(\.value).min()), 0.000001)
        }
    }

    func testShorterThanOneStepIntervalIsRefined() throws {
        let values = try samples(peak: 0.12, duration: 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(values.map(\.value).max()), -0.000001)
    }

    func testValuesNeverReadOutsideIntervalAndDatesAreUnique() throws {
        let interval = DateInterval(start: start, duration: 1_210)
        let values = try SearchSampling.samples(in: interval, step: 300, tolerance: 0.0001, iterations: 48) {
            XCTAssertGreaterThanOrEqual($0, interval.start)
            XCTAssertLessThanOrEqual($0, interval.end)
            return sin($0.timeIntervalSince(self.start) / 300)
        }
        XCTAssertEqual(values.first?.date, interval.start)
        XCTAssertEqual(values.last?.date, interval.end)
        XCTAssertEqual(Set(values.map(\.date)).count, values.count)
        for (a, b) in zip(values, values.dropFirst()) { XCTAssertLessThan(a.date, b.date) }
    }

    func testFlatFunctionDoesNotRefineEveryInteriorGridPoint() throws {
        var calls = 0
        let values = try SearchSampling.samples(in: DateInterval(start: start, duration: 86_400),
            step: 60, tolerance: 0.02, iterations: 32) { _ in calls += 1; return 2 }
        XCTAssertTrue(values.allSatisfy { $0.value == 2 })
        XCTAssertLessThan(calls, 1_700)
    }

    func testInvalidStepIsRejectedBeforeEvaluation() throws {
        for step in [0, -1, Double.nan, Double.infinity, -Double.infinity,
                     Double.leastNonzeroMagnitude] {
            var calls = 0
            XCTAssertThrowsError(try SearchSampling.samples(in: DateInterval(start: start, duration: 1_200),
                step: step, tolerance: 0.0001, iterations: 48) { _ in calls += 1; return 0 }) {
                    XCTAssertEqual($0 as? LightPlanError, .invalidNumber)
                }
            XCTAssertEqual(calls, 0)
        }
    }

    func testZeroLengthIntervalIsRejected() throws {
        XCTAssertThrowsError(try SearchSampling.samples(in: DateInterval(start: start, duration: 0),
            step: 300, tolerance: 0.0001, iterations: 48) { _ in 0 }) {
                XCTAssertEqual($0 as? LightPlanError, .invalidDate)
            }
    }

    func testNonfiniteValuesAreRejected() throws {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try SearchSampling.samples(in: DateInterval(start: start, duration: 1_200),
                step: 300, tolerance: 0.0001, iterations: 48) { _ in bad }) {
                    XCTAssertEqual($0 as? LightPlanError, .invalidNumber)
                }
        }
    }

    func testNonfiniteValueDuringRefinementIsRejected() throws {
        XCTAssertThrowsError(try SearchSampling.samples(in: DateInterval(start: start, duration: 1_200),
            step: 300, tolerance: 0.0001, iterations: 48) {
                let offset = $0.timeIntervalSince(self.start)
                return offset.truncatingRemainder(dividingBy: 300) == 0 ? 0 : .nan
            }) { XCTAssertEqual($0 as? LightPlanError, .invalidNumber) }
    }

    func testCancellationPropagatesWithoutReturningPartialSamples() async throws {
        let start = self.start
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SearchSampling.samples(in: DateInterval(start: start, duration: 86_400),
                step: 60, tolerance: 0.02, iterations: 32) { _ in 0 }
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must not publish partial samples")
        } catch is CancellationError { }
    }
}
