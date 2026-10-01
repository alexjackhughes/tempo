import SwiftUI

/// Resolves segments to categories using the configured rules.
struct Categorizer {
    private let byID: [UUID: Category]
    private let appRules: [String: UUID]
    private let domainRules: [String: UUID]
    private let hiddenApps: Set<String>
    private let hiddenDomains: Set<String>

    init(config: Config) {
        byID = Dictionary(config.categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var apps: [String: UUID] = [:]
        var domains: [String: UUID] = [:]
        for rule in config.rules {
            let pattern = rule.pattern.lowercased()
            switch rule.kind {
            case .app: apps[pattern] = rule.categoryID
            case .domain: domains[pattern] = rule.categoryID
            }
        }
        appRules = apps
        domainRules = domains
        hiddenApps = Set(config.hidden.filter { $0.kind == .app }.map { $0.value.lowercased() })
        hiddenDomains = Set(config.hidden.filter { $0.kind == .domain }.map { $0.value.lowercased() })
    }

    func isHidden(_ segment: ActivitySegment) -> Bool {
        if let domain = segment.domain {
            guard !hiddenDomains.isEmpty else { return false }
            let labels = domain.split(separator: ".")
            return labels.indices.contains { hiddenDomains.contains(labels[$0...].joined(separator: ".")) }
        }
        return hiddenApps.contains(segment.app.lowercased()) || hiddenApps.contains(segment.bundleID.lowercased())
    }

    func category(for segment: ActivitySegment) -> Category? {
        // Most specific domain match wins: "mail.google.com" before "google.com".
        if let domain = segment.domain {
            let labels = domain.split(separator: ".")
            for i in labels.indices {
                let suffix = labels[i...].joined(separator: ".")
                if let id = domainRules[suffix], let category = byID[id] { return category }
            }
        }
        if let id = appRules[segment.bundleID.lowercased()] ?? appRules[segment.app.lowercased()] {
            return byID[id]
        }
        return nil
    }

    static func itemKey(for segment: ActivitySegment) -> ItemKey {
        if let domain = segment.domain { return ItemKey(kind: .domain, value: domain) }
        return ItemKey(kind: .app, value: segment.app)
    }
}

struct CategoryTotal: Identifiable {
    let category: Category?
    let seconds: TimeInterval

    var id: String { category?.id.uuidString ?? "uncategorized" }
    var name: String { category?.name ?? "Uncategorized" }
    var color: Color { category?.color ?? T.fg3.opacity(0.5) }
    var productivity: Productivity { category?.productivity ?? .neutral }
}

struct ItemTotal: Identifiable {
    let key: ItemKey
    let app: String
    let seconds: TimeInterval
    let category: Category?

    var id: ItemKey { key }
}

struct Summary {
    var total: TimeInterval = 0
    var categories: [CategoryTotal] = []
    var items: [ItemTotal] = []
    var byProductivity: [Productivity: TimeInterval] = [:]

    /// 0–100, weighted by productivity. Nil when there's too little data to be meaningful.
    var score: Double? {
        guard total >= 60 else { return nil }
        let weighted = byProductivity.reduce(0) { $0 + $1.key.weight * $1.value }
        return weighted / total * 100
    }

    func seconds(_ productivity: Productivity) -> TimeInterval { byProductivity[productivity] ?? 0 }

    init() {}

    init(segments: [ActivitySegment], categorizer: Categorizer) {
        var categoryTotals: [UUID?: (Category?, TimeInterval)] = [:]
        var itemTotals: [ItemKey: (String, TimeInterval, Category?)] = [:]

        for segment in segments {
            let seconds = segment.duration
            guard seconds > 0, !categorizer.isHidden(segment) else { continue }
            let category = categorizer.category(for: segment)
            total += seconds
            byProductivity[category?.productivity ?? .neutral, default: 0] += seconds

            let existing = categoryTotals[category?.id] ?? (category, 0)
            categoryTotals[category?.id] = (category, existing.1 + seconds)

            let key = Categorizer.itemKey(for: segment)
            let item = itemTotals[key] ?? (segment.app, 0, category)
            itemTotals[key] = (item.0, item.1 + seconds, category)
        }

        categories = categoryTotals.values
            .map { CategoryTotal(category: $0.0, seconds: $0.1) }
            .sorted { $0.seconds > $1.seconds }
        items = itemTotals
            .map { ItemTotal(key: $0.key, app: $0.value.0, seconds: $0.value.1, category: $0.value.2) }
            .sorted { $0.seconds > $1.seconds }
    }
}

struct HourBucket: Identifiable {
    let hour: Int
    let productivity: Productivity
    let minutes: Double

    var id: String { "\(hour)-\(productivity.rawValue)" }
}

func hourlyBreakdown(_ segments: [ActivitySegment], categorizer: Categorizer) -> [HourBucket] {
    let calendar = Calendar.current
    var totals: [Int: [Productivity: TimeInterval]] = [:]
    for segment in segments where segment.duration > 0 && !categorizer.isHidden(segment) {
        let productivity = categorizer.category(for: segment)?.productivity ?? .neutral
        var cursor = segment.start
        while cursor < segment.end {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)!
            let chunkEnd = min(segment.end, hourStart.end)
            totals[hour, default: [:]][productivity, default: 0] += chunkEnd.timeIntervalSince(cursor)
            cursor = chunkEnd
        }
    }
    return totals.flatMap { hour, byProductivity in
        byProductivity.map { HourBucket(hour: hour, productivity: $0.key, minutes: $0.value / 60) }
    }
}

struct DayStat: Identifiable {
    let date: Date
    let summary: Summary
    let pomodorosCompleted: Int
    let pomodoroScore: Double?

    var id: Date { date }
}
