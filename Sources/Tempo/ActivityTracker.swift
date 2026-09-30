import AppKit
import CoreGraphics

/// Samples the frontmost app (and browser site) every few seconds and on every app switch.
final class ActivityTracker {
    static let sampleInterval: TimeInterval = 5

    private let store: Store
    let browser = BrowserURLReader()
    private var timer: Timer?
    private var suspended = false
    private var observers: [NSObjectProtocol] = []

    init(store: Store) {
        self.store = store
    }

    func start() {
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.sample() })

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspend(true)
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspend(false)
            })
        }

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.suspend(true) })
        observers.append(distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.suspend(false) })

        sample()
    }

    private func suspend(_ value: Bool) {
        suspended = value
        if value { store.breakContinuity() } else { sample() }
    }

    func sample() {
        let now = Date()
        guard !store.trackingPaused, !suspended else {
            store.breakContinuity()
            return
        }

        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= store.config.idleThreshold {
            store.breakContinuity(endAt: now.addingTimeInterval(-idle))
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleID = app.bundleIdentifier ?? ""
        if bundleID == "com.apple.loginwindow" || bundleID == "com.apple.ScreenSaver.Engine" {
            store.breakContinuity()
            return
        }

        let name = app.localizedName ?? bundleID
        let domain = store.config.trackBrowserURLs ? browser.domain(for: bundleID) : nil
        store.record(app: name, bundleID: bundleID, domain: domain, at: now,
                     maxGap: Self.sampleInterval * 2.5)
    }
}

/// Reads the active tab's URL from browsers via AppleScript (asks for Automation permission once per browser).
final class BrowserURLReader {
    private static let safariLike: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    ]
    private static let chromiumLike: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.operasoftware.Opera",
    ]

    private var scripts: [String: NSAppleScript] = [:]
    private(set) var deniedBrowsers: Set<String> = []

    static func isSupportedBrowser(_ bundleID: String) -> Bool {
        safariLike.contains(bundleID) || chromiumLike.contains(bundleID)
    }

    func domain(for bundleID: String) -> String? {
        let source: String
        if Self.safariLike.contains(bundleID) {
            source = "tell application id \"\(bundleID)\" to get URL of front document"
        } else if Self.chromiumLike.contains(bundleID) {
            source = "tell application id \"\(bundleID)\" to get URL of active tab of front window"
        } else {
            return nil
        }

        let script = scripts[bundleID] ?? NSAppleScript(source: source)!
        scripts[bundleID] = script

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { deniedBrowsers.insert(bundleID) }
            return nil
        }
        deniedBrowsers.remove(bundleID)

        guard let string = result.stringValue, let host = URL(string: string)?.host?.lowercased() else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
