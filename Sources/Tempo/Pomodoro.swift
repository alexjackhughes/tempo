import AppKit
import Observation
import UserNotifications

@Observable
final class Pomodoro {
    /// idle → focus → breakReady (waits for you) → rest → idle
    enum Phase: String, Equatable { case idle, focus, breakReady, rest }

    private(set) var phase: Phase = .idle
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var task = ""
    private(set) var now = Date()
    /// Set when a focus session or break finishes; cleared once you open the popover.
    private(set) var needsAttention = false
    /// The focus session that just finished, shown while waiting to start the break.
    private(set) var lastSession: PomodoroSession?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private var timer: Timer?

    init(store: Store) {
        self.store = store
        restore()
    }

    // MARK: Persistence — the current state survives quitting, crashes and updates.

    private struct SavedState: Codable {
        var phase: String
        var start: Date?
        var end: Date?
        var task: String
        var needsAttention: Bool?
        var lastSessionID: UUID?
    }

    private var stateURL: URL { store.directory.appendingPathComponent("active-session.json") }

    private func persist() {
        guard phase != .idle || needsAttention else {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        let state = SavedState(phase: phase.rawValue, start: startDate, end: endDate, task: task,
                               needsAttention: needsAttention, lastSessionID: lastSession?.id)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data),
              let phase = Phase(rawValue: state.phase) else { return }
        self.phase = phase
        startDate = state.start
        endDate = state.end
        task = state.task
        needsAttention = state.needsAttention ?? false
        lastSession = state.lastSessionID.flatMap { id in store.sessions.first { $0.id == id } }
        if phase == .focus || phase == .rest {
            startTimer()
            tick() // completes the phase right away if it ended while Tempo wasn't running
        }
    }

    private func startTimer() {
        now = Date()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: State

    var remaining: TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(now))
    }

    var elapsed: TimeInterval {
        guard let startDate else { return 0 }
        return max(0, now.timeIntervalSince(startDate))
    }

    var progress: Double {
        guard let startDate, let endDate else { return 0 }
        let total = endDate.timeIntervalSince(startDate)
        return total > 0 ? min(1, elapsed / total) : 0
    }

    // MARK: Actions

    func startFocus(task: String) {
        self.task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSession = nil
        begin(.focus, minutes: store.config.focusMinutes)
    }

    /// Ends the current focus session early. A session of 1+ minute is kept as "incomplete".
    func stop() {
        if phase == .focus, let startDate, elapsed >= 60 {
            store.addSession(PomodoroSession(
                start: startDate, end: Date(), plannedMinutes: store.config.focusMinutes,
                task: task, completed: false))
        }
        reset()
    }

    func startBreak() {
        begin(.rest, minutes: store.config.breakMinutes)
    }

    /// Skips a pending or running break and goes back to the focus timer.
    func skipBreak() { reset() }

    /// The user has seen the "done" state (opened the popover).
    func acknowledge() {
        guard needsAttention else { return }
        needsAttention = false
        persist()
    }

    private func begin(_ phase: Phase, minutes: Int) {
        let start = Date()
        self.phase = phase
        needsAttention = false
        startDate = start
        endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        startTimer()
        persist()
    }

    private func reset(attention: Bool = false) {
        phase = .idle
        startDate = nil
        endDate = nil
        needsAttention = attention
        stopTimer()
        persist()
    }

    private func tick() {
        now = Date()
        guard let endDate, now >= endDate else { return }

        switch phase {
        case .focus:
            let session = PomodoroSession(
                start: startDate ?? endDate, end: endDate, plannedMinutes: store.config.focusMinutes,
                task: task, completed: true)
            store.addSession(session)
            lastSession = session
            let score = store.score(for: session).map { " · focus score \(Int($0.rounded()))" } ?? ""
            let done = store.sessions(on: .now).filter(\.completed).count
            Notifier.send(
                title: "Focus session complete",
                body: "\(task.isEmpty ? "Session" : task) done\(score). \(done) today. Start your \(store.config.breakMinutes) min break from the menu bar.")
            // Wait for the user to start the break rather than starting it unseen.
            phase = .breakReady
            startDate = nil
            self.endDate = nil
            needsAttention = true
            stopTimer()
            persist()
        case .rest:
            Notifier.send(title: "Break's over", body: "Ready for another focus session?")
            reset(attention: true)
        case .idle, .breakReady:
            stopTimer()
        }
    }
}

enum Notifier {
    /// Notification APIs only work from the packaged .app (not `swift run` or the test runner).
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        NSSound(named: "Glass")?.play()
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
