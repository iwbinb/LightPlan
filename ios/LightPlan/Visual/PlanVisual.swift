import SwiftUI
import LightPlanCore

struct PlansView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @State private var create = false
    @State private var deleting: ShootPlan?
    var openPaywall: () -> Void
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if state.plans.isEmpty {
                    LPPhotoHero(asset: "hero-sunset", minimumHeight: 290) {
                        VStack(alignment: .leading, spacing: 10) { KeyText("v3.plan.emptyTitle").font(.largeTitle.bold()); KeyText("plan.emptyBody").font(.body); KeyText("v3.art.label").font(.caption2).opacity(0.7) }
                    }.clipShape(RoundedRectangle(cornerRadius: 28))
                    Button(action: createPlan) { Label(L10n.text("plan.create"), systemImage: "calendar.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(15) }.buttonStyle(.borderedProminent)
                }
                ForEach(state.plans.sorted { $0.date < $1.date }) { plan in
                    NavigationLink { PlanDetailView(plan: plan) } label: {
                        LPPhotoHero(asset: "hero-sunset", minimumHeight: 205) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(plan.title).font(.title2.bold()).multilineTextAlignment(.leading)
                                Label(plan.place.name, systemImage: "mappin.circle.fill").font(.subheadline)
                                HStack { Text(L10n.fullDate(plan.date, zone: plan.place.timeZone)); Spacer(); Image(systemName: "arrow.up.right") }.font(.caption)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 26))
                    }.buttonStyle(LPPressStyle()).accessibilityIdentifier("plan-card")
                        .contextMenu { Button(role: .destructive) { deleting = plan } label: { Label(L10n.text("common.delete"), systemImage: "trash") } }
                }
            }.padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(LPTheme.canvas).navigationTitle(L10n.text("tab.plans"))
            .toolbar { Button(action: createPlan) { Image(systemName: "plus").accessibilityLabel(L10n.text("plan.create")) }.accessibilityIdentifier("plan-create") }
            .sheet(isPresented: $create) { NavigationStack { PlanEditorView() } }
            .confirmationDialog(L10n.text("plan.deleteConfirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(L10n.text("common.delete"), role: .destructive) { if let plan = deleting { Task { await state.deletePlan(plan) } }; deleting = nil }
            }
            .navigationDestination(item: $state.openPlanID) { id in
                if let plan = state.plans.first(where: { $0.id == id }) { PlanDetailView(plan: plan) }
                else { KeyText("plan.notFound") }
            }
            .accessibilityIdentifier("screen-plans")
    }
    private func createPlan() { state.requestPremium(unlocked: purchases.unlocked) { create = true } }
}
struct PlanDetailView: View {
    let plan: ShootPlan
    @EnvironmentObject private var purchases: PurchaseStore
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var milestones: [PlanMilestone] = []
    @State private var problem = false
    @State private var editing = false
    @State private var deleting = false
    private var current: ShootPlan { state.plans.first(where: { $0.id == plan.id }) ?? plan }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LPPhotoHero(asset: "hero-sunset", minimumHeight: typeSize.isAccessibilitySize ? 400 : 310) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            LPCircleButton(symbol: "chevron.left", label: "v3.back") { dismiss() }
                            Spacer()
                            Button { state.requestPremium(unlocked: purchases.unlocked) { editing = true } } label: { Label(L10n.text("v3.edit"), systemImage: "pencil").font(.subheadline.weight(.semibold)).padding(12).lpGlass(radius: 22) }.buttonStyle(.plain)
                        }
                        Spacer(minLength: 45)
                        Text(current.title).font(.system(.largeTitle, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Label(L10n.fullDate(current.date, zone: current.place.timeZone), systemImage: "calendar").font(.subheadline)
                        Label(current.place.name, systemImage: "mappin.circle.fill").font(.subheadline)
                        KeyText("v3.art.label").font(.caption2).opacity(0.7)
                    }
                }
                VStack(alignment: .leading, spacing: 24) {
                    HStack { KeyText("plan.schedule").font(.title2.bold()); Spacer(); Image(systemName: "clock").foregroundStyle(.secondary) }
                    VStack(spacing: 0) {
                        ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                            LPMilestoneRow(item: milestone, zone: current.place.timeZone, last: index == milestones.count - 1)
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
                        }
                    }
                    HStack {
                        Button(L10n.text("plan.duplicate")) { state.requestPremium(unlocked: purchases.unlocked) { state.duplicate(current) } }
                        Spacer()
                        Button(L10n.text("common.delete"), role: .destructive) { deleting = true }
                    }
                    if current.reminderLeadMinutes != nil { Button(L10n.text("plan.stopReminder")) { Task { await state.stopReminder(current) } } }
                    KeyText("plan.arrivalNote").font(.caption).foregroundStyle(.secondary)
                    KeyText("disclaimer.geometry").font(.caption).foregroundStyle(.secondary)
                }.padding(22).background(LPTheme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)).padding(.top, -15)
            }.frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(LPTheme.canvas).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button { Task { await state.showPlanMap(current); dismiss() } } label: {
                    Label(L10n.text("v3.plan.viewMap"), systemImage: "map.fill").font(.headline).frame(maxWidth: .infinity).padding(16).foregroundStyle(.white).background(LPTheme.ink, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(LPPressStyle()).padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
            }
            .confirmationDialog(L10n.text("plan.deleteConfirm"), isPresented: $deleting, titleVisibility: .visible) {
                Button(L10n.text("common.delete"), role: .destructive) { Task { await state.deletePlan(current); dismiss() } }
            }
            .sheet(isPresented: $editing) { NavigationStack { PlanEditorView(planToEdit: current) } }
            .task(id: current.updatedAt) {
                problem = false
                let snapshot = current
                do { let summary = try await Task.detached { try DayEngine.calculate(place: snapshot.place, date: snapshot.date) }.value; milestones = try Planner.milestones(plan: snapshot, summary: summary) }
                catch { problem = true; milestones = [] }
            }
            .accessibilityIdentifier("screen-plan-detail")
    }
}
struct LPMilestoneRow: View {
    let item: PlanMilestone
    let zone: TimeZone
    let last: Bool
    private var tint: Color {
        if item.key.contains("blue") || item.key.contains("goldenEveningEnd") { return LPTheme.blue }
        if item.key.contains("sunset") { return LPTheme.sunset }
        if item.key == "plan.arrival" { return .secondary }
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
            Text(L10n.time(item.date, zone: zone)).font(.body.weight(.semibold)).monospacedDigit().frame(minWidth: 65, alignment: .leading)
            VStack(spacing: 0) { Circle().fill(tint).frame(width: 11, height: 11).padding(.top, 5); Rectangle().fill(last ? .clear : .secondary.opacity(0.2)).frame(width: 1).frame(minHeight: 43) }.frame(width: 13)
            VStack(alignment: .leading, spacing: 5) { KeyText(item.key).font(.headline).fixedSize(horizontal: false, vertical: true); Text(hintKey.map { L10n.text($0) } ?? zone.identifier).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(.bottom, 23)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}
