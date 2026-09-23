import Foundation

public enum FieldSessionPhase: String, Sendable {
    case beforeArrival, preparing, shooting, passed, completed
}

/// A countdown describes the saved schedule, never predicted visibility or weather.
/// All comparisons use absolute instants, including repeated destination clock times.
public struct FieldSessionStatus: Equatable, Sendable {
    public let phase: FieldSessionPhase
    public let secondsRemaining: TimeInterval?

    public init(arriveAt: Date, shootAt: Date, completedAt: Date?, now: Date) throws {
        guard arriveAt.timeIntervalSince1970.isFinite, shootAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite, completedAt?.timeIntervalSince1970.isFinite != false,
              arriveAt.timeIntervalSince(now).isFinite, shootAt.timeIntervalSince(now).isFinite,
              arriveAt <= shootAt else { throw LightPlanError.invalidDate }
        if completedAt != nil {
            phase = .completed; secondsRemaining = nil
        } else if now < arriveAt {
            phase = .beforeArrival; secondsRemaining = max(0, ceil(arriveAt.timeIntervalSince(now)))
        } else if now < shootAt {
            phase = .preparing; secondsRemaining = max(0, ceil(shootAt.timeIntervalSince(now)))
        } else if now.timeIntervalSince(shootAt) < 60 {
            phase = .shooting; secondsRemaining = nil
        } else {
            phase = .passed; secondsRemaining = nil
        }
    }
}
