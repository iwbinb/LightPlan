import SwiftUI
import LightPlanCore

struct FieldSessionView: View {
    let plan: ShootPlan
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var summary: DaySummary?
    @State private var loading = true
    @State private var failed = false
    @State private var completing = false
    @State private var completionFailed = false
    @State private var retryID = UUID()

    private var current: ShootPlan { state.plans.first(where: { $0.id == plan.id }) ?? plan }
    private var brief: PlanFieldBrief? {
        guard let summary else { return nil }
        return try? PlanFieldBrief(plan: current, summary: summary)
    }
    private struct Calculation: Equatable {
        let place: Place
        let date: Date
        let retryID: UUID
    }
    private var calculation: Calculation { Calculation(place: current.place, date: current.date, retryID: retryID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Label(current.place.name, systemImage: "mappin.circle.fill").font(.headline)
                        Text(L10n.text("target." + current.target.rawValue)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let completedAt = current.completedAt, brief == nil {
                        completionWithoutSchedule(completedAt)
                    }
                    if let brief {
                        FieldCountdownView(brief: brief)
                        LPCard {
                            VStack(alignment: .leading, spacing: 18) {
                                scheduleRow(key: "plan.arrival", date: brief.arriveAt, symbol: "figure.walk")
                                Divider()
                                scheduleRow(key: "brief.shootAt", date: brief.shootAt, symbol: "camera.viewfinder")
                                Text(current.place.timeZoneID).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        FieldBriefView(brief: brief)
                    } else {
                        LPCard {
                            VStack(alignment: .leading, spacing: 12) {
                                if loading { ProgressView().accessibilityLabel(L10n.text("plan.preview")) }
                                else {
                                    KeyText(failed ? "error.calculation" : "plan.noEvent").font(.headline)
                                        .accessibilityIdentifier(current.completedAt == nil ? "field-session-status" : "field-session-error")
                                    if failed { Button(L10n.text("library.retry")) { retryID = UUID() } }
                                }
                                Text(L10n.fullDate(current.date, zone: current.place.timeZone))
                                Text(current.place.timeZoneID + " · " + L10n.utcOffset(at: current.date, zone: current.place.timeZone))
                                    .font(.caption).foregroundStyle(.secondary)
                                LabeledContent(L10n.text("brief.observer"), value: L10n.coordinate(current.place.coordinate))
                                if let notes = current.notes, !notes.isEmpty {
                                    Divider()
                                    KeyText("plan.notes").font(.headline)
                                    Text(notes).textSelection(.enabled).accessibilityIdentifier("saved-plan-notes")
                                }
                            }
                        }
                    }
                    Button {
                        guard !completing else { return }
                        completing = true; completionFailed = false
                        let requestedCompletion = current.completedAt == nil
                        Task {
                            await state.setPlanCompleted(current, completed: requestedCompletion, showNotice: false)
                            completionFailed = (current.completedAt != nil) != requestedCompletion
                            completing = false
                        }
                    } label: {
                        Label(L10n.text(current.completedAt == nil ? "library.markCompleted" : "library.reopen"),
                              systemImage: current.completedAt == nil ? "checkmark.circle.fill" : "arrow.uturn.backward")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(completing)
                        .accessibilityIdentifier("field-session-complete")
                    if completionFailed { KeyText("error.save").foregroundStyle(.red) }
                    KeyText("field.scheduleNote").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(LPTheme.canvas).navigationTitle(L10n.text("field.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.close")) { dismiss() }.accessibilityIdentifier("field-session-close")
                }
            }
            .task(id: calculation) { await load(calculation) }
        }
    }

    private func scheduleRow(key: String, date: Date, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.text(key), systemImage: symbol).font(.headline)
            Text(L10n.time(date, zone: current.place.timeZone)).font(.title2.bold()).monospacedDigit()
            Text(L10n.fullDate(date, zone: current.place.timeZone) + " · " + L10n.utcOffset(at: date, zone: current.place.timeZone))
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func completionWithoutSchedule(_ date: Date) -> some View {
        LPCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("library.filter.completed"), systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).accessibilityIdentifier("field-session-status")
                Text(L10n.fullDate(date, zone: current.place.timeZone) + " · " + L10n.time(date, zone: current.place.timeZone))
            }
        }
    }

    private func load(_ input: Calculation) async {
        guard !Task.isCancelled else { return }
        loading = true; failed = false; summary = nil
        let worker = Task.detached(priority: .userInitiated) { try DayEngine.calculate(place: input.place, date: input.date) }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard calculation == input else { return }
            summary = value; loading = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, calculation == input else { return }
            failed = true; loading = false
        }
    }
}

/// Its timeline invalidates only the countdown card. DayEngine and the field brief
/// remain outside this closure; foregrounding derives fresh time from the clock.
private struct FieldCountdownView: View {
    let brief: PlanFieldBrief

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let status = try? FieldSessionStatus(arriveAt: brief.arriveAt, shootAt: brief.shootAt,
                                                   completedAt: brief.plan.completedAt, now: timeline.date) {
                LPCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.text("field.phase." + status.phase.rawValue), systemImage: symbol(status.phase))
                            .font(.headline).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("field-session-status")
                        if let seconds = status.secondsRemaining {
                            Text(duration(seconds)).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("field-session-countdown")
                        }
                        if status.phase == .preparing { KeyText("field.readyNote").foregroundStyle(.secondary) }
                        if let completedAt = brief.plan.completedAt {
                            Text(L10n.fullDate(completedAt, zone: brief.plan.place.timeZone) + " · " + L10n.time(completedAt, zone: brief.plan.place.timeZone))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ phase: FieldSessionPhase) -> String {
        switch phase {
        case .beforeArrival: return "figure.walk"
        case .preparing: return "camera"
        case .shooting: return "camera.viewfinder"
        case .passed: return "clock.badge.checkmark"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian); calendar.locale = L10n.locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 3
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: max(0, seconds)) ?? L10n.number(max(0, seconds))
    }
}
