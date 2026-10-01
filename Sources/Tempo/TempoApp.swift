import AppKit
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let openDashboard = Notification.Name("TempoOpenDashboard")
}

@Observable
final class AppModel {
    static let shared = AppModel()

    let store: Store
    let pomodoro: Pomodoro
    @ObservationIgnored let tracker: ActivityTracker
    @ObservationIgnored private var saveTimer: Timer?

    init(store: Store = Store()) {
        self.store = store
        pomodoro = Pomodoro(store: store)
        tracker = ActivityTracker(store: store)
    }

    func start() {
        tracker.start()
        Notifier.requestAuthorization()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.store.flush() }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Fonts.register()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Notifier.available { UNUserNotificationCenter.current().delegate = self }
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.store.breakContinuity()
        AppModel.shared.store.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching Tempo again (Finder, Spotlight, Dock) while it's running opens the dashboard,
    /// so it's reachable even if the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
        return true
    }

    // Show banners even while Tempo is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct TempoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(AppModel.shared)
        } label: {
            MenuBarLabel()
                .environment(AppModel.shared)
        }
        .menuBarExtraStyle(.window)

        Window("Tempo", id: "dashboard") {
            DashboardView()
                .environment(AppModel.shared)
        }
        .defaultSize(width: 1080, height: 760)
    }
}
