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
}
