import AppKit
import SwiftUI
import XCTest
@testable import Tempo

/// Renders the main screens with generated data. Set TEMPO_SNAPSHOT_DIR to write PNGs.
final class SnapshotTests: XCTestCase {
    @MainActor
    func testRenderScreens() throws {
        guard let out = ProcessInfo.processInfo.environment["TEMPO_SNAPSHOT_DIR"] else {
            throw XCTSkip("TEMPO_SNAPSHOT_DIR not set")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        seed(store)
        let model = AppModel(store: store)

        render(MenuBarView().environment(model), size: CGSize(width: 320, height: 520), to: "\(out)/menubar.png")
        render(DayView().environment(model), size: CGSize(width: 1000, height: 1300), to: "\(out)/day.png")
        render(TrendsView().environment(model), size: CGSize(width: 1000, height: 1400), to: "\(out)/trends.png")
        render(PomodorosView().environment(model), size: CGSize(width: 1000, height: 900), to: "\(out)/pomodoros.png")
        render(CategoriesView().environment(model), size: CGSize(width: 1000, height: 900), to: "\(out)/categories.png")
    }

    private func seed(_ store: Store) {
        let calendar = Calendar.current
        let activities: [(String, String?)] = [
            ("Xcode", nil), ("Cursor", nil), ("Safari", "github.com"), ("Slack", nil), ("Arc", "youtube.com"),
            ("Arc", "x.com"), ("Notion", nil), ("Arc", "docs.google.com"), ("Arc", "somerandomblog.io"),
            ("Mail", nil), ("Terminal", nil), ("Arc", "reddit.com"),
        ]
        var rng = SystemRandomNumberGenerator()
        for dayOffset in (0..<21).reversed() {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: .now))!
            let focusBias = 0.4 + Double(21 - dayOffset) / 40 // improving over time
            var t = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            let end = min(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!, .now)
            var pomodoroStart: Date?
            while t < end {
                let productive = Double.random(in: 0...1, using: &rng) < focusBias
                let pick = productive
                    ? [0, 1, 2, 6, 7, 10].randomElement(using: &rng)!
                    : [3, 4, 5, 8, 9, 11].randomElement(using: &rng)!
                let (app, domain) = activities[pick]
                let minutes = Int.random(in: 2...14, using: &rng)
                for s in stride(from: 0, through: minutes * 60, by: 5) {
                    store.record(app: app, bundleID: "id.\(app)", domain: domain,
                                 at: t.addingTimeInterval(TimeInterval(s)), maxGap: 12.5)
                }
                t = t.addingTimeInterval(TimeInterval(minutes * 60))
                if pomodoroStart == nil, Int.random(in: 0...3, using: &rng) == 0 {
                    pomodoroStart = t
                } else if let start = pomodoroStart, t.timeIntervalSince(start) >= 1200 {
                    store.addSession(PomodoroSession(start: start, end: start.addingTimeInterval(1200),
                                                     plannedMinutes: 20, task: ["Auth refactor", "Write blog post", "Inbox zero", "Design review"].randomElement(using: &rng)!,
                                                     completed: Int.random(in: 0...5, using: &rng) > 0))
                    pomodoroStart = nil
                }
            }
            store.breakContinuity()
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, size: CGSize, to path: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
