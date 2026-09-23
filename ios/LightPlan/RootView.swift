import SwiftUI
import LightPlanCore

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("language") private var language = "system"
    @AppStorage("clockFormat") private var clockFormat = "system"
    var body: some View {
        TabView(selection: $state.tab) {
            NavigationStack { TodayView() }.tabItem { Label(L10n.text("tab.today"), systemImage: "sun.max") }.tag(0)
            NavigationStack { LightMapView() }.tabItem { Label(L10n.text("tab.map"), systemImage: "map") }.tag(1)
            NavigationStack { PlansView() }.tabItem { Label(L10n.text("tab.plans"), systemImage: "calendar") }.tag(2)
            NavigationStack { PlacesView() }.tabItem { Label(L10n.text("tab.places"), systemImage: "mappin.and.ellipse") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label(L10n.text("tab.settings"), systemImage: "gearshape") }.tag(4)
        }
        .tint(LPTheme.accent)
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })) {
            OnboardingView { choosePlace in
                if choosePlace { state.tab = 3 }
                onboardingDone = true
            }
        }
        .alert(L10n.text("common.notice"), isPresented: Binding(get: { state.errorKey != nil || state.noticeKey != nil }, set: { if !$0 { state.errorKey = nil; state.noticeKey = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) { state.errorKey = nil; state.noticeKey = nil }
        } message: { Text(L10n.text(state.errorKey ?? state.noticeKey ?? "common.notice")) }
        .onChange(of: clockFormat) { _, _ in
            state.publishWidget()
            Task { await ReminderService.reconcile(plans: state.plans, language: L10n.language) }
        }
        .onChange(of: state.place) { _, _ in state.publishWidget() }
        .onChange(of: language) { _, _ in
            state.publishWidget()
            Task { await ReminderService.reconcile(plans: state.plans, language: L10n.language) }
        }
    }
}
struct OnboardingView: View {
    var finish: (Bool) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "sun.horizon.fill").font(.system(size: 60)).foregroundStyle(LPTheme.accent)
                KeyText("onboarding.title").font(.largeTitle.bold())
                KeyText("onboarding.body").font(.title3)
                Label(L10n.text("onboarding.offline"), systemImage: "wifi.slash")
                Label(L10n.text("onboarding.privacy"), systemImage: "lock.shield")
                KeyText("onboarding.caveat").font(.footnote).foregroundStyle(.secondary)
                KeyText("guide.steps").font(.body)
                Button { finish(true) } label: { KeyText("guide.choosePlace").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent).accessibilityIdentifier("onboarding-start")
                Button { finish(false) } label: { KeyText("guide.exploreExample") }.buttonStyle(.bordered)
            }.padding(28).padding(.top, 28)
        }.interactiveDismissDisabled()
    }
}
