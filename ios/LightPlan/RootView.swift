import SwiftUI
import LightPlanCore

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("language") private var language = "system"
    @AppStorage("clockFormat") private var clockFormat = "system"
    var body: some View {
        TabView(selection: $state.tab) {
            NavigationStack { TodayView(openPaywall: showPaywall) }.tabItem { Label(L10n.text("tab.today"), systemImage: "sun.max") }.tag(0)
            NavigationStack { LightMapView(openPaywall: showPaywall) }.tabItem { Label(L10n.text("tab.map"), systemImage: "map") }.tag(1)
            NavigationStack { PlansView(openPaywall: showPaywall) }.tabItem { Label(L10n.text("tab.plans"), systemImage: "calendar") }.tag(2)
            NavigationStack { PlacesView(openPaywall: showPaywall) }.tabItem { Label(L10n.text("tab.places"), systemImage: "mappin.and.ellipse") }.tag(3)
            NavigationStack { SettingsView(openPaywall: showPaywall) }.tabItem { Label(L10n.text("tab.settings"), systemImage: "gearshape") }.tag(4)
        }
        .tint(LPTheme.accent)
        .sheet(isPresented: $state.paywallPresented, onDismiss: { state.paywallClosed(unlocked: purchases.unlocked) }) { PaywallView() }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })) { OnboardingView { onboardingDone = true } }
        .alert(L10n.text("common.notice"), isPresented: Binding(get: { state.errorKey != nil || state.noticeKey != nil }, set: { if !$0 { state.errorKey = nil; state.noticeKey = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) { state.errorKey = nil; state.noticeKey = nil }
        } message: { Text(L10n.text(state.errorKey ?? state.noticeKey ?? "common.notice")) }
        .onChange(of: purchases.unlocked) { _, value in
            state.publishWidget(unlocked: value)
            if value { state.paywallPresented = false }
        }
        .onChange(of: clockFormat) { _, _ in
            state.publishWidget(unlocked: purchases.unlocked)
            Task { await ReminderService.reconcile(plans: state.plans, language: L10n.language) }
        }
        .onChange(of: state.place) { _, _ in state.publishWidget(unlocked: purchases.unlocked) }
        .onChange(of: language) { _, _ in
            state.publishWidget(unlocked: purchases.unlocked)
            Task { await ReminderService.reconcile(plans: state.plans, language: L10n.language) }
        }
    }
    private func showPaywall() { state.paywallPresented = true }
}
struct OnboardingView: View {
    var finish: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "sun.horizon.fill").font(.system(size: 60)).foregroundStyle(LPTheme.accent)
                KeyText("onboarding.title").font(.largeTitle.bold())
                KeyText("onboarding.body").font(.title3)
                Label(L10n.text("onboarding.offline"), systemImage: "wifi.slash")
                Label(L10n.text("onboarding.privacy"), systemImage: "lock.shield")
                KeyText("onboarding.caveat").font(.footnote).foregroundStyle(.secondary)
                Button(action: finish) { KeyText("onboarding.start").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent).accessibilityIdentifier("onboarding-start")
            }.padding(28).padding(.top, 28)
        }.interactiveDismissDisabled()
    }
}
