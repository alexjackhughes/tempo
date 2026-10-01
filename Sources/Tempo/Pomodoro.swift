import AppKit
import Observation
import UserNotifications

@Observable
final class Pomodoro {
    enum Phase: Equatable { case idle, focus, rest }

    private(set) var phase: Phase = .idle
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var task = ""
    private(set) var now = Date()

    @ObservationIgnored private let store: Store
    @ObservationIgnored private var timer: Timer?

    init(store: Store) {
        self.store = store
        restore()
    }

    // MARK: Persistence — a running session survives quitting, crashes and updates.

    private struct SavedState: Codable {
        var phase: String
        var start: Date
        var end: Date
        var task: String
    }

    private var stateURL: URL { store.directory.appendingPathComponent("active-session.json") }

    private func persist() {
        guard let startDate, let endDate, phase != .idle else {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        let state = SavedState(phase: phase == .focus ? "focus" : "rest", start: startDate, end: endDate, task: task)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        phase = state.phase == "focus" ? .focus : .rest
        startDate = state.start
        endDate = state.end
        task = state.task
        startTimer()
        tick() // completes the phase right away if it ended while Tempo wasn't running
    }

    private func startTimer() {
        now = Date()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

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

    func startFocus(task: String) {
        let minutes = store.config.focusMinutes
        self.task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        begin(.focus, minutes: minutes)
    }

    /// Ends the current phase early. A focus session of 1+ minute is kept as "incomplete".
    func stop() {
        if phase == .focus, let startDate, elapsed >= 60 {
            store.addSession(PomodoroSession(
                start: startDate, end: Date(), plannedMinutes: store.config.focusMinutes,
                task: task, completed: false))
        }
        reset()
    }

    func skipBreak() { reset() }

    private func begin(_ phase: Phase, minutes: Int) {
        let start = Date()
        self.phase = phase
        startDate = start
        endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        startTimer()
        persist()
    }

    private func reset() {
        phase = .idle
        startDate = nil
        endDate = nil
        timer?.invalidate()
        timer = nil
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
            let score = store.score(for: session).map { " · focus score \(Int($0.rounded()))" } ?? ""
            let done = store.sessions(on: .now).filter(\.completed).count
            Notifier.send(
                title: "Pomodoro complete 🎉",
                body: "\(task.isEmpty ? "Session" : task) done\(score). \(done) today — time for a \(store.config.breakMinutes) min break.")
            begin(.rest, minutes: store.config.breakMinutes)
        case .rest:
            Notifier.send(title: "Break's over", body: "Ready for another round?")
            reset()
        case .idle:
            reset()
        }
    }
}

enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

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
