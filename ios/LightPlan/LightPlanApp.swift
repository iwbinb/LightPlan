import SwiftUI
import UserNotifications
import LightPlanCore

@main struct LightPlanApp: App {
    @StateObject private var state = AppState()
    @AppStorage("language") private var language = "system"
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(state)
                .environment(\.locale, language == "system" ? .autoupdatingCurrent : Locale(identifier: language))
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task {
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    await state.refresh()
                    state.publishWidget()
                    await state.reconcileReminders()
                }
                .task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        await state.tick()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await state.tick()
                            state.publishWidget()
                            await state.reconcileReminders()
                        }
                    }
                }
                .onOpenURL(perform: open)
                .onReceive(NotificationCenter.default.publisher(for: .lightPlanOpenPlan)) { note in
                    if let id = note.object as? UUID { openPlan(id) }
                }
        }
    }
    private func open(_ url: URL) {
        guard url.scheme == "lightplan" else { return }
        switch url.host {
        case "today": state.tab = 0; Task { await state.showToday() }
        case "plans", "plan":
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
               let id = UUID(uuidString: value) { openPlan(id) } else { state.tab = 2 }
        default: break
        }
    }
    private func openPlan(_ id: UUID) {
        state.tab = 2
        guard state.plans.contains(where: { $0.id == id }) else { state.noticeKey = "plan.notFound"; return }
        state.openPlanID = id
    }
}
