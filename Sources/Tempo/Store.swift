import Foundation
import Observation

/// Local JSON persistence for config, activity (one file per day) and pomodoro sessions.
///
/// Layout: ~/Library/Application Support/Tempo/
///   config.json, sessions.json, activity/yyyy-MM-dd.json
@Observable
final class Store {
    var config: Config
    private(set) var sessions: [PomodoroSession] = []
    /// Bumped whenever activity is recorded so views refresh.
    private(set) var revision = 0
    var trackingPaused = false

    @ObservationIgnored let directory: URL
    @ObservationIgnored private var savedConfig: Config
    @ObservationIgnored private var days: [String: [ActivitySegment]] = [:]
    @ObservationIgnored private var dirtyDays: Set<String> = []
    @ObservationIgnored private var current: (day: String, index: Int)?
    @ObservationIgnored private var lastTick: Date?

    @ObservationIgnored private var cachedCategorizer: Categorizer
    @ObservationIgnored private var categorizerConfig: Config
    @ObservationIgnored private var summaryCache: [String: Summary] = [:]
    @ObservationIgnored private var sessionScoreCache: [UUID: Double?] = [:]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? support.appendingPathComponent("Tempo", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.directory.appendingPathComponent("activity"), withIntermediateDirectories: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let loadedConfig = (try? Data(contentsOf: self.directory.appendingPathComponent("config.json")))
            .flatMap { try? decoder.decode(Config.self, from: $0) }
        let config = loadedConfig ?? Config.defaults()
        self.config = config
        savedConfig = loadedConfig ?? config
        cachedCategorizer = Categorizer(config: config)
        categorizerConfig = config
        sessions = (try? Data(contentsOf: self.directory.appendingPathComponent("sessions.json")))
            .flatMap { try? decoder.decode([PomodoroSession].self, from: $0) } ?? []

        if loadedConfig == nil { writeConfig() }
    }

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    var categorizer: Categorizer {
        if categorizerConfig != config {
            cachedCategorizer = Categorizer(config: config)
            categorizerConfig = config
            summaryCache = [:]
            sessionScoreCache = [:]
        }
        return cachedCategorizer
    }

    // MARK: Recording

    func record(app: String, bundleID: String, domain: String?, at now: Date, maxGap: TimeInterval) {
        let key = Store.dayKey(now)
        if let last = lastTick, now.timeIntervalSince(last) <= maxGap, let cur = current {
            // Credit the time since the last sample to what was on screen then.
            days[cur.day]?[cur.index].end = now
            dirtyDays.insert(cur.day)
            if cur.day == key,
               let seg = days[cur.day]?[cur.index],
               seg.isSameActivity(app: app, bundleID: bundleID, domain: domain) {
                lastTick = now
                revision += 1
                return
            }
        }
        _ = load(key)
        days[key, default: []].append(
            ActivitySegment(start: now, end: now, app: app, bundleID: bundleID, domain: domain))
        current = (key, days[key]!.count - 1)
        dirtyDays.insert(key)
        lastTick = now
        revision += 1
    }

    /// Stop extending the current segment (idle, sleep, lock, pause).
    /// `endAt` trims the segment back to when the user actually went idle.
    func breakContinuity(endAt: Date? = nil) {
        guard let cur = current else { lastTick = nil; return }
        if var seg = days[cur.day]?[cur.index] {
            if let endAt, endAt < seg.end { seg.end = max(seg.start, endAt) }
            if seg.duration < 1, cur.index == days[cur.day]!.count - 1 {
                days[cur.day]!.removeLast()
            } else {
                days[cur.day]![cur.index] = seg
            }
            dirtyDays.insert(cur.day)
            revision += 1
        }
        current = nil
        lastTick = nil
    }

    // MARK: Queries

    func segments(on day: Date) -> [ActivitySegment] {
        _ = revision
        return load(Store.dayKey(day))
    }

    func segments(in interval: DateInterval) -> [ActivitySegment] {
        _ = revision
        let calendar = Calendar.current
        var result: [ActivitySegment] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            for var seg in load(Store.dayKey(day)) where seg.end > interval.start && seg.start < interval.end {
                seg.start = max(seg.start, interval.start)
                seg.end = min(seg.end, interval.end)
                result.append(seg)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    func summary(for day: Date) -> Summary {
        let key = Store.dayKey(day)
        let categorizer = self.categorizer
        let isPast = day < Calendar.current.startOfDay(for: .now)
        if isPast, let cached = summaryCache[key] { return cached }
        let summary = Summary(segments: segments(on: day), categorizer: categorizer)
        if isPast { summaryCache[key] = summary }
        return summary
    }

    func summary(in interval: DateInterval) -> Summary {
        Summary(segments: segments(in: interval), categorizer: categorizer)
    }

    func sessions(on day: Date) -> [PomodoroSession] {
        let calendar = Calendar.current
        return sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    func score(for session: PomodoroSession) -> Double? {
        _ = categorizer // invalidates cache on rule changes
        let isFinal = session.end < Date().addingTimeInterval(-60)
        if isFinal, let cached = sessionScoreCache[session.id] { return cached }
        let score = summary(in: session.interval).score
        if isFinal { sessionScoreCache[session.id] = score }
        return score
    }

    func dayStats(days count: Int, endingOn end: Date = .now) -> [DayStat] {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: end)
        return (0..<count).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: lastDay)!
            let done = sessions(on: day).filter(\.completed)
            let scores = done.compactMap { score(for: $0) }
            return DayStat(
                date: day,
                summary: summary(for: day),
                pomodorosCompleted: done.count,
                pomodoroScore: scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count))
        }
    }

    // MARK: Mutations

    func assign(_ item: ItemKey, to categoryID: UUID?) {
        let pattern = item.value.lowercased()
        config.rules.removeAll { $0.kind == item.kind && $0.pattern == pattern }
        if let categoryID {
            config.rules.append(Rule(kind: item.kind, pattern: pattern, categoryID: categoryID))
        }
        saveConfigIfNeeded()
    }

    func deleteCategory(_ id: UUID) {
        config.categories.removeAll { $0.id == id }
        config.rules.removeAll { $0.categoryID == id }
        saveConfigIfNeeded()
    }

    func addSession(_ session: PomodoroSession) {
        sessions.append(session)
        writeSessions()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        writeSessions()
    }

    // MARK: Persistence

    func flush() {
        for key in dirtyDays {
            guard let segs = days[key], let data = try? encoder.encode(segs) else { continue }
            try? data.write(to: dayURL(key), options: .atomic)
        }
        dirtyDays.removeAll()
        saveConfigIfNeeded()
    }

    func saveConfigIfNeeded() {
        guard config != savedConfig else { return }
        writeConfig()
    }

    private func writeConfig() {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(config) else { return }
        try? data.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        savedConfig = config
    }

    private func writeSessions() {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: directory.appendingPathComponent("sessions.json"), options: .atomic)
    }

    private func dayURL(_ key: String) -> URL {
        directory.appendingPathComponent("activity/\(key).json")
    }

    private func load(_ key: String) -> [ActivitySegment] {
        if let segs = days[key] { return segs }
        let segs = (try? Data(contentsOf: dayURL(key)))
            .flatMap { try? decoder.decode([ActivitySegment].self, from: $0) } ?? []
        days[key] = segs
        return segs
    }
}
