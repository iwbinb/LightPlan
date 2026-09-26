import SwiftUI
import LightPlanCore

struct PlanDetailView: View {
    let plan: ShootPlan
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var milestones: [PlanMilestone] = []
    @State private var problem = false
    @State private var editing = false
    @State private var fieldSession = false
    @State private var deleting = false
    @State private var day: DaySummary?
    @State private var reminderStatusKey = "settings.notificationUnknown"
    @State private var reminderBusy = false
    private var current: ShootPlan { state.plans.first(where: { $0.id == plan.id }) ?? plan }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LPPhotoHero(asset: "hero-sunset", minimumHeight: typeSize.isAccessibilitySize ? 400 : 310) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            LPCircleButton(symbol: "chevron.left", label: "v3.back") { dismiss() }
                            Spacer()
                            Button { editing = true } label: { Label(L10n.text("v3.edit"), systemImage: "pencil").font(.subheadline.weight(.semibold)).padding(12).lpGlass(radius: 22) }.buttonStyle(.plain).accessibilityIdentifier("plan-edit")
                        }
                        Spacer(minLength: 45)
                        Text(current.title).font(.system(.largeTitle, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("screen-plan-detail")
                        Label(L10n.fullDate(current.date, zone: current.place.timeZone), systemImage: "calendar").font(.subheadline)
                        Label(current.place.name, systemImage: "mappin.circle.fill").font(.subheadline)
                        if let name = current.collectionName, !name.isEmpty { Label(name, systemImage: "folder").font(.subheadline) }
                        if current.completedAt != nil { Label(L10n.text("library.completed"), systemImage: "checkmark.circle.fill").font(.subheadline) }
                        KeyText("v3.art.label").font(.caption2).opacity(0.7)
                    }
                }
                VStack(alignment: .leading, spacing: 24) {
                    if typeSize.isAccessibilitySize {
                        // Large-text users should not traverse the entire brief to
                        // reach field mode, nor lose the viewport to a fixed tall CTA.
                        fieldModeButton
                        viewMapButton.accessibilityIdentifier("plan-inline-view-map")
                    }
                    if let day, let brief = try? PlanFieldBrief(plan: current, summary: day) {
                        FieldBriefView(brief: brief)
                    } else if let notes = current.notes, !notes.isEmpty {
                        LPCard {
                            VStack(alignment: .leading, spacing: 10) {
                                KeyText("plan.notes").font(.headline)
                                Text(notes).textSelection(.enabled).accessibilityIdentifier("saved-plan-notes")
                            }
                        }
                    }
                    if let composition = current.composition {
                        if let framing = composition.cameraFraming {
                            LPCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    KeyText("frame.saved").font(.headline)
                                    FramingDiagram(framing: framing, place: current.place, subject: composition.subject,
                                        celestialBody: composition.body, instant: composition.instant, compact: true)
                                    KeyText("frame.modelNote").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        LPCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(L10n.text("target.composition"), systemImage: "camera.viewfinder").font(.headline)
                                LabeledContent { Text(L10n.text("body." + composition.body.rawValue)).accessibilityIdentifier("saved-composition-body") } label: { KeyText("map.body") }
                                LabeledContent { Text(L10n.coordinate(composition.subject)).accessibilityIdentifier("saved-composition-subject") } label: { KeyText("composition.subject") }
                                LabeledContent { Text(L10n.number(composition.desiredOffsetDegrees, decimals: 1) + "°").accessibilityIdentifier("saved-composition-offset") } label: { KeyText("composition.targetOffset") }
                                Text(L10n.time(composition.instant, zone: current.place.timeZone))
                                    .font(.title2.monospacedDigit()).accessibilityIdentifier("saved-composition-time")
                                Text(current.place.timeZoneID).font(.caption).foregroundStyle(.secondary)
                                if let constraints = composition.constraints {
                                    Text(L10n.conditions(constraints)).font(.caption).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("saved-composition-conditions")
                                }
                                if let alignment = try? CompositionPlanner.evaluate(body: composition.body, at: composition.instant,
                                    observer: current.place.coordinate, subject: composition.subject,
                                    desiredOffsetDegrees: composition.desiredOffsetDegrees) {
                                    LabeledContent(L10n.text("composition.error"), value: L10n.number(alignment.absoluteErrorDegrees, decimals: 1) + "°")
                                    Text(L10n.text("composition.quality." + alignment.quality.rawValue))
                                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("saved-composition-quality")
                                    Text(L10n.text("composition.side." + alignment.side.rawValue)).font(.caption).foregroundStyle(.secondary)
                                }
                                KeyText("composition.geometryNote").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack { KeyText("plan.schedule").font(.title2.bold()); Spacer(); Image(systemName: "clock").foregroundStyle(.secondary) }
                    VStack(spacing: 0) {
                        ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                            LPMilestoneRow(item: milestone, zone: current.place.timeZone, day: current.date, last: index == milestones.count - 1)
                        }
                    }
                    if problem { KeyText("plan.noEvent").foregroundStyle(.secondary) }
                    LPCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(L10n.text("plan.remind"), systemImage: "bell.badge").font(.headline)
                            if let minutes = current.reminderLeadMinutes {
                                Text(L10n.text("plan.reminderLead") + " " + L10n.number(Double(minutes)) + " " + L10n.text("unit.minutes")).font(.subheadline)
                            } else { KeyText("v3.reminder.off").font(.subheadline) }
                            KeyText("v3.reminder.note").font(.caption).foregroundStyle(.secondary)
                            KeyText(reminderStatusKey).font(.subheadline).accessibilityIdentifier("plan-reminder-status")
                            if canRetryReminder {
                                Button(L10n.text("plan.retryReminder")) {
                                    Task { await retryReminder() }
                                }.disabled(reminderBusy)
                            }
                        }
                    }
                    HStack {
                        Button(L10n.text("plan.duplicate")) { state.duplicate(current) }.accessibilityIdentifier("plan-duplicate")
                        Spacer()
                        Button(L10n.text("common.delete"), role: .destructive) { deleting = true }.accessibilityIdentifier("plan-delete")
                    }
                    if !typeSize.isAccessibilitySize { fieldModeButton }
                    Button(L10n.text(current.completedAt == nil ? "library.markCompleted" : "library.reopen")) {
                        Task { await state.setPlanCompleted(current, completed: current.completedAt == nil) }
                    }.accessibilityIdentifier("plan-toggle-completed")
                    if current.reminderLeadMinutes != nil { Button(L10n.text("plan.stopReminder")) { Task { await state.stopReminder(current) } }.accessibilityIdentifier("plan-stop-reminder") }
                    KeyText("plan.arrivalNote").font(.caption).foregroundStyle(.secondary)
                    KeyText("disclaimer.geometry").font(.caption).foregroundStyle(.secondary)
                }.padding(22).background(LPTheme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)).padding(.top, -15)
            }.frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(LPTheme.canvas).toolbar(.hidden, for: .navigationBar)
            .labeledContentStyle(LPReadableMetricStyle())
            .safeAreaInset(edge: .bottom) {
                if !typeSize.isAccessibilitySize {
                    viewMapButton.accessibilityIdentifier("plan-view-map")
                        .padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
                }
            }
            .confirmationDialog(L10n.text("plan.deleteConfirm"), isPresented: $deleting, titleVisibility: .visible) {
                Button(L10n.text("common.delete"), role: .destructive) { Task { if await state.deletePlan(current) { dismiss() } } }
            }
            .sheet(isPresented: $editing) { NavigationStack { PlanEditorView(planToEdit: current) } }
            .sheet(isPresented: $fieldSession) { FieldSessionView(plan: current) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let day {
                    Task { reminderStatusKey = await ReminderService.statusKey(plan: current, summary: day) }
                }
            }
            .task(id: current) {
                problem = false; day = nil; milestones = []
                let snapshot = current
                do {
                    let worker = Task.detached { try DayEngine.calculate(place: snapshot.place, date: snapshot.date) }
                    let summary = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    guard !Task.isCancelled, current == snapshot else { return }
                    milestones = try Planner.milestones(plan: snapshot, summary: summary)
                    day = summary
                    let status = await ReminderService.statusKey(plan: snapshot, summary: summary)
                    if !Task.isCancelled, current == snapshot { reminderStatusKey = status }
                }
                catch is CancellationError { }
                catch { if !Task.isCancelled, current == snapshot { problem = true; milestones = []; day = nil } }
            }
    }
    private var fieldModeButton: some View {
        Button { fieldSession = true } label: {
            Label(L10n.text("library.openField"), systemImage: "viewfinder")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity).padding(14)
        }.buttonStyle(.borderedProminent).accessibilityIdentifier("plan-field-mode")
    }

    private var viewMapButton: some View {
        Button { Task { await state.showPlanMap(current); dismiss() } } label: {
            Label(L10n.text("v3.plan.viewMap"), systemImage: "map.fill").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity).padding(16).foregroundStyle(.white)
                .background(LPTheme.ink, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(LPPressStyle())
    }

    private var canRetryReminder: Bool {
        guard reminderStatusKey != "plan.reminderScheduled", let day else { return false }
        return Planner.reminder(plan: current, summary: day, now: Date()) != nil
    }
    private func retryReminder() async {
        guard let day, !reminderBusy else { return }
        reminderBusy = true; defer { reminderBusy = false }
        do { _ = try await state.scheduleReminder(for: current, summary: day) }
        catch { state.noticeKey = "notice.savedWithoutReminder" }
        reminderStatusKey = await ReminderService.statusKey(plan: current, summary: day)
    }
}
struct LPMilestoneRow: View {
    let item: PlanMilestone
    let zone: TimeZone
    let day: Date
    let last: Bool
    private var tint: Color {
        if item.key.contains("blue") || item.key.contains("goldenEveningEnd") { return LPTheme.blue }
        if item.key.contains("sunset") { return LPTheme.sunset }
        if item.key == "plan.arrival" { return .secondary }
        if item.key == "target.composition" { return .purple }
        return LPTheme.gold
    }
    private var hintKey: String? {
        switch item.key {
        case "plan.arrival": return "v3.plan.arriveHint"
        case "event.goldenEveningStart": return "v3.plan.goldenHint"
        case "event.sunset": return "v3.plan.sunsetHint"
        case "event.goldenEveningEnd": return "v3.plan.blueHint"
        case "event.blueEveningEnd": return "v3.plan.blueEndHint"
        default: return nil
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.time(item.date, zone: zone)).font(.body.weight(.semibold)).monospacedDigit()
                if !LocalDay.same(item.date, day, timeZone: zone) {
                    Text(L10n.fullDate(item.date, zone: zone)).font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(minWidth: 65, alignment: .leading)
            VStack(spacing: 0) { Circle().fill(tint).frame(width: 11, height: 11).padding(.top, 5); Rectangle().fill(last ? .clear : .secondary.opacity(0.2)).frame(width: 1).frame(minHeight: 43) }.frame(width: 13)
            VStack(alignment: .leading, spacing: 5) { KeyText(item.key).font(.headline).fixedSize(horizontal: false, vertical: true); Text(hintKey.map { L10n.text($0) } ?? zone.identifier).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(.bottom, 23)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}
