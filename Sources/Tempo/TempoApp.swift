import AppKit
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let openDashboard = Notification.Name("TempoOpenDashboard")
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var detail: String?
    var undo: (() -> Void)?
}

@Observable
final class AppModel {
    static let shared = AppModel()

    let store: Store
    let pomodoro: Pomodoro
    @ObservationIgnored let tracker: ActivityTracker
    @ObservationIgnored private var saveTimer: Timer?
    /// Transient confirmation shown at the bottom of the dashboard.
    private(set) var toast: Toast?

    init(store: Store = Store()) {
        self.store = store
        pomodoro = Pomodoro(store: store)
        tracker = ActivityTracker(store: store)
    }

    func show(_ toast: Toast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }

    func dismissToast() { toast = nil }

    func start() {
        tracker.start()
        Notifier.requestAuthorization()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.store.flush() }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set only by the explicit "Quit Tempo" command; ⌘Q and Dock → Quit just close the dashboard.
    private static var quitRequested = false
    private var termSource: DispatchSourceSignal?

    static func quit() {
        quitRequested = true
        NSApp.terminate(nil)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Fonts.register()
        // `kill`/installer updates: save activity and the running session before exiting.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            AppModel.shared.store.breakContinuity()
            AppModel.shared.store.flush()
            exit(0)
        }
        source.resume()
        termSource = source
    }

    /// Tempo lives in the menu bar and should keep tracking. Quitting from the Dock or with ⌘Q
    /// (while the dashboard is open) only closes the dashboard; logout, restart and shutdown still quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isSystemQuit = event?.attributeDescriptor(forKeyword: kAEQuitReason) != nil
        if Self.quitRequested || isSystemQuit { return .terminateNow }

        for window in NSApp.windows where window.isVisible && window.level == .normal {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
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
