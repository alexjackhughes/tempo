import XCTest
@testable import Tempo

final class TempoTests: XCTestCase {
    private var directory: URL!
    private var store: Store!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = Store(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private let base = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!

    private func sample(_ offset: TimeInterval, _ app: String, _ domain: String? = nil) {
        store.record(app: app, bundleID: "id.\(app)", domain: domain, at: base.addingTimeInterval(offset), maxGap: 12.5)
    }

    func testConsecutiveSamplesMergeIntoOneSegment() {
        for t in stride(from: 0.0, through: 60, by: 5) { sample(t, "Xcode") }
        let segs = store.segments(on: base)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].duration, 60)
    }

    func testSwitchingCreditsTimeToPreviousActivity() {
        sample(0, "Xcode"); sample(5, "Xcode"); sample(10, "Safari", "youtube.com"); sample(15, "Safari", "youtube.com")
        let segs = store.segments(on: base)
        XCTAssertEqual(segs.map(\.duration), [10, 5])
        XCTAssertEqual(segs[1].domain, "youtube.com")
    }

    func testIdleTrimsSegmentAndBreaksContinuity() {
        for t in stride(from: 0.0, through: 300, by: 5) { sample(t, "Xcode") }
        store.breakContinuity(endAt: base.addingTimeInterval(120)) // user went idle at +2 min
        sample(1000, "Xcode")
        let segs = store.segments(on: base)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].duration, 120)
    }

    func testGapLargerThanMaxGapStartsNewSegment() {
        sample(0, "Xcode"); sample(5, "Xcode"); sample(60, "Xcode")
        XCTAssertEqual(store.segments(on: base).count, 2)
    }

    func testCategorizerPrefersMostSpecificDomain() {
        let c = store.categorizer
        let mail = ActivitySegment(start: base, end: base, app: "Safari", bundleID: "com.apple.Safari", domain: "mail.google.com")
        let docs = ActivitySegment(start: base, end: base, app: "Chrome", bundleID: "x", domain: "docs.google.com")
        let yt = ActivitySegment(start: base, end: base, app: "Chrome", bundleID: "x", domain: "m.youtube.com")
        let code = ActivitySegment(start: base, end: base, app: "Xcode", bundleID: "com.apple.dt.Xcode", domain: nil)
        XCTAssertEqual(c.category(for: mail)?.name, "Communication")
        XCTAssertEqual(c.category(for: docs)?.name, "Work & Docs")
        XCTAssertEqual(c.category(for: yt)?.name, "Entertainment")
        XCTAssertEqual(c.category(for: code)?.name, "Development")
    }

    func testScoreAndReassignmentAppliesRetroactively() {
        // Xcode is credited until the switch at 65s, youtube 65→120s.
        for t in stride(from: 0.0, through: 60, by: 5) { sample(t, "Xcode") }
        for t in stride(from: 65.0, through: 120, by: 5) { sample(t, "Safari", "youtube.com") }
        store.breakContinuity()
        let before = store.summary(in: DateInterval(start: base, end: base.addingTimeInterval(120))).score!
        XCTAssertEqual(before, 65.0 / 120 * 100, accuracy: 0.1)

        let dev = store.config.categories.first { $0.name == "Development" }!
        store.assign(ItemKey(kind: .domain, value: "youtube.com"), to: dev.id)
        let after = store.summary(in: DateInterval(start: base, end: base.addingTimeInterval(120))).score!
        XCTAssertEqual(after, 100, accuracy: 0.1)
    }

    func testPomodoroSessionScoreUsesOnlyItsWindow() {
        for t in stride(from: 0.0, through: 600, by: 5) { sample(t, "Xcode") }
        for t in stride(from: 605.0, through: 1200, by: 5) { sample(t, "Safari", "reddit.com") }
        let session = PomodoroSession(start: base, end: base.addingTimeInterval(600), plannedMinutes: 10,
                                      task: "test", completed: true)
        XCTAssertEqual(store.score(for: session)!, 100, accuracy: 0.1)
    }

    func testPersistenceRoundTrip() {
        for t in stride(from: 0.0, through: 30, by: 5) { sample(t, "Xcode") }
        store.addSession(PomodoroSession(start: base, end: base.addingTimeInterval(1200), plannedMinutes: 20,
                                         task: "write", completed: true))
        store.config.focusMinutes = 25
        store.flush()

        let reloaded = Store(directory: directory)
        XCTAssertEqual(reloaded.segments(on: base).first?.duration, 30)
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.config.focusMinutes, 25)
    }

    func testBroaderDomain() {
        XCTAssertEqual(ItemKey(kind: .domain, value: "app-eu1.hubspot.com").broaderDomain, "hubspot.com")
        XCTAssertEqual(ItemKey(kind: .domain, value: "news.bbc.co.uk").broaderDomain, "bbc.co.uk")
        XCTAssertNil(ItemKey(kind: .domain, value: "youtube.com").broaderDomain)
        XCTAssertNil(ItemKey(kind: .domain, value: "meet.google.com").broaderDomain) // shared root
        XCTAssertNil(ItemKey(kind: .app, value: "Xcode").broaderDomain)
    }

    func testDomainWideAssignmentCoversOtherSubdomainsAndClearsExactRule() {
        let dev = store.config.categories.first { $0.name == "Development" }!
        let social = store.config.categories.first { $0.name == "Social Media" }!
        let exact = ItemKey(kind: .domain, value: "app-eu1.hubspot.com")
        store.assign(exact, to: social.id)
        store.assign(ItemKey(kind: .domain, value: "hubspot.com"), to: dev.id, clearing: [exact])
        let other = ActivitySegment(start: base, end: base, app: "Dia", bundleID: "x", domain: "app.hubspot.com")
        let original = ActivitySegment(start: base, end: base, app: "Dia", bundleID: "x", domain: "app-eu1.hubspot.com")
        XCTAssertEqual(store.categorizer.category(for: other)?.name, "Development")
        XCTAssertEqual(store.categorizer.category(for: original)?.name, "Development")
    }

    func testDeleteAndIgnorePurgesHistoryAndStopsRecording() {
        let yesterday = base.addingTimeInterval(-86_400)
        for t in stride(from: 0.0, through: 60, by: 5) {
            store.record(app: "Dia", bundleID: "dia", domain: "m.youtube.com", at: yesterday.addingTimeInterval(t), maxGap: 12.5)
        }
        store.breakContinuity()
        for t in stride(from: 0.0, through: 60, by: 5) { sample(t, "Xcode") }
        for t in stride(from: 65.0, through: 120, by: 5) { sample(t, "Safari", "youtube.com") }
        store.breakContinuity()

        let item = ItemKey(kind: .domain, value: "youtube.com")
        XCTAssertEqual(store.recordedTime(for: item), 60 + 55, accuracy: 0.1)
        XCTAssertEqual(store.deleteAndIgnore(item), 60 + 55, accuracy: 0.1)

        // Gone from disk, not just from view.
        let reloaded = Store(directory: directory)
        XCTAssertTrue(reloaded.segments(on: yesterday).isEmpty)
        XCTAssertEqual(reloaded.segments(on: base).map(\.domain), [nil])
        XCTAssertTrue(reloaded.categorizer.isIgnored(app: "Arc", bundleID: "arc", domain: "music.youtube.com"))

        // Resuming only affects the future.
        reloaded.resumeTracking(item)
        XCTAssertFalse(reloaded.categorizer.isIgnored(app: "Arc", bundleID: "arc", domain: "youtube.com"))
        XCTAssertTrue(reloaded.segments(on: yesterday).isEmpty)
    }

    func testIgnoringAnAppCoversItsWebsites() {
        let item = ItemKey(kind: .app, value: "Dia")
        var config = store.config
        config.ignored = [item]
        let matcher = Categorizer(config: config)
        XCTAssertTrue(matcher.isIgnored(app: "Dia", bundleID: "company.thebrowser.dia", domain: "github.com"))
        XCTAssertFalse(matcher.isIgnored(app: "Safari", bundleID: "com.apple.Safari", domain: "github.com"))
    }

    func testRunningSessionSurvivesRestart() {
        let pomodoro = Pomodoro(store: store)
        pomodoro.startFocus(task: "Write tests")
        let restored = Pomodoro(store: Store(directory: directory))
        XCTAssertEqual(restored.phase, .focus)
        XCTAssertEqual(restored.task, "Write tests")
        XCTAssertEqual(restored.endDate, pomodoro.endDate)
        restored.stop()
        XCTAssertEqual(Pomodoro(store: Store(directory: directory)).phase, .idle)
    }

    /// Simulates time passing by rewriting the saved state's end date, then reloading.
    private func expireSavedPhase() {
        let url = directory.appendingPathComponent("active-session.json")
        var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["end"] = Date().addingTimeInterval(-1).timeIntervalSinceReferenceDate
        try! JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    func testFocusCompletionWaitsForBreakAndNeedsAcknowledgement() {
        Pomodoro(store: store).startFocus(task: "Ship it")
        expireSavedPhase()

        var p = Pomodoro(store: Store(directory: directory))
        XCTAssertEqual(p.phase, .breakReady, "break must not start on its own")
        XCTAssertTrue(p.needsAttention)
        XCTAssertEqual(p.lastSession?.task, "Ship it")
        XCTAssertEqual(Store(directory: directory).sessions.filter(\.completed).count, 1)

        p.acknowledge()
        XCTAssertFalse(Pomodoro(store: Store(directory: directory)).needsAttention, "acknowledgement persists")

        p = Pomodoro(store: Store(directory: directory))
        p.startBreak()
        XCTAssertEqual(p.phase, .rest)
        XCTAssertEqual(p.remaining, TimeInterval(store.config.breakMinutes * 60), accuracy: 2)
        expireSavedPhase()

        p = Pomodoro(store: Store(directory: directory))
        XCTAssertEqual(p.phase, .idle)
        XCTAssertTrue(p.needsAttention, "break ending is flagged in the menu bar")
        p.acknowledge()
        XCTAssertEqual(Pomodoro(store: Store(directory: directory)).phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("active-session.json").path))
    }

    func testSkippingPendingBreakReturnsToFocusTimer() {
        Pomodoro(store: store).startFocus(task: "")
        expireSavedPhase()
        let p = Pomodoro(store: Store(directory: directory))
        p.skipBreak()
        XCTAssertEqual(p.phase, .idle)
        XCTAssertFalse(p.needsAttention)
    }
}
