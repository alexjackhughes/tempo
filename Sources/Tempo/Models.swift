import SwiftUI

/// A continuous stretch of time spent in one app (and, for browsers, one site).
struct ActivitySegment: Codable, Hashable {
    var start: Date
    var end: Date
    var app: String
    var bundleID: String
    var domain: String?

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    func isSameActivity(app: String, bundleID: String, domain: String?) -> Bool {
        self.app == app && self.bundleID == bundleID && self.domain == domain
    }
}

enum Productivity: String, Codable, CaseIterable, Identifiable {
    case productive, neutral, distracting

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Contribution to the 0–100 productivity score.
    var weight: Double {
        switch self {
        case .productive: 1
        case .neutral: 0.5
        case .distracting: 0
        }
    }

}

struct Category: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String
    var productivity: Productivity

    var color: Color { Color(hex: colorHex) }
}

enum RuleKind: String, Codable, CaseIterable {
    case app, domain
}

/// Maps an app (by name or bundle ID) or a website domain to a category.
struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: RuleKind
    var pattern: String
    var categoryID: UUID
}

struct PomodoroSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var plannedMinutes: Int
    var task: String
    var completed: Bool

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

struct Config: Codable, Equatable {
    var categories: [Category]
    var rules: [Rule]
    var focusMinutes = 20
    var breakMinutes = 5
    var idleThreshold: TimeInterval = 180
    var trackBrowserURLs = true
    var dailyPomodoroGoal = 8

    init(categories: [Category], rules: [Rule]) {
        self.categories = categories
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decode([Category].self, forKey: .categories)
        rules = try c.decode([Rule].self, forKey: .rules)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 20
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 5
        idleThreshold = try c.decodeIfPresent(TimeInterval.self, forKey: .idleThreshold) ?? 180
        trackBrowserURLs = try c.decodeIfPresent(Bool.self, forKey: .trackBrowserURLs) ?? true
        dailyPomodoroGoal = try c.decodeIfPresent(Int.self, forKey: .dailyPomodoroGoal) ?? 8
    }
}

struct ItemKey: Hashable {
    var kind: RuleKind
    var value: String
}

// MARK: - Defaults

extension Config {
    static let palette = [
        "#0070F3", "#12A594", "#30A46C", "#6E56CF", "#8E4EC6",
        "#E93D82", "#E5484D", "#F76B15", "#FFB224", "#AD7F58", "#8F8F8F",
    ]

    /// Maps the original system-style colours onto the Geist palette.
    static let legacyPalette: [String: String] = [
        "#0A84FF": "#0070F3", "#30B0C7": "#12A594", "#34C759": "#30A46C", "#5856D6": "#6E56CF",
        "#AF52DE": "#8E4EC6", "#FF2D55": "#E93D82", "#FF3B30": "#E5484D", "#FF9500": "#F76B15",
        "#FFCC00": "#FFB224", "#A2845E": "#AD7F58", "#8E8E93": "#8F8F8F",
    ]

    static func defaults() -> Config {
        var categories: [Category] = []
        var rules: [Rule] = []

        func add(_ name: String, _ hex: String, _ productivity: Productivity, apps: [String], domains: [String]) {
            let category = Category(name: name, colorHex: hex, productivity: productivity)
            categories.append(category)
            rules += apps.map { Rule(kind: .app, pattern: $0.lowercased(), categoryID: category.id) }
            rules += domains.map { Rule(kind: .domain, pattern: $0.lowercased(), categoryID: category.id) }
        }

        add("Development", "#0070F3", .productive,
            apps: ["Xcode", "Code", "Cursor", "Zed", "Terminal", "iTerm2", "Warp", "Ghostty", "Claude",
                   "Simulator", "Docker Desktop", "TablePlus", "Postman", "GitHub Desktop", "Tower"],
            domains: ["github.com", "gitlab.com", "stackoverflow.com", "vercel.com", "localhost", "127.0.0.1",
                      "developer.apple.com", "developer.mozilla.org", "claude.ai", "chatgpt.com",
                      "npmjs.com", "supabase.com", "console.anthropic.com"])
        add("Work & Docs", "#12A594", .productive,
            apps: ["Notion", "Linear", "Figma", "Obsidian", "Notes", "Pages", "Numbers", "Keynote",
                   "Microsoft Word", "Microsoft Excel", "Microsoft PowerPoint", "Preview", "Things", "Craft"],
            domains: ["docs.google.com", "drive.google.com", "notion.so", "linear.app", "figma.com",
                      "miro.com", "airtable.com", "trello.com", "asana.com", "atlassian.net"])
        add("Communication", "#6E56CF", .neutral,
            apps: ["Slack", "Mail", "Messages", "zoom.us", "Discord", "Microsoft Teams", "WhatsApp",
                   "Telegram", "Signal", "FaceTime", "Calendar", "Superhuman", "Spark"],
            domains: ["mail.google.com", "calendar.google.com", "meet.google.com", "outlook.live.com",
                      "outlook.office.com", "app.slack.com", "web.whatsapp.com", "zoom.us"])
        add("Social Media", "#E93D82", .distracting,
            apps: [],
            domains: ["x.com", "twitter.com", "facebook.com", "instagram.com", "reddit.com", "linkedin.com",
                      "tiktok.com", "threads.net", "bsky.app", "news.ycombinator.com", "pinterest.com"])
        add("Entertainment", "#E5484D", .distracting,
            apps: ["Spotify", "Music", "TV", "Podcasts", "Steam", "Netflix"],
            domains: ["youtube.com", "netflix.com", "twitch.tv", "primevideo.com", "disneyplus.com",
                      "open.spotify.com", "bbc.co.uk", "theguardian.com", "nytimes.com", "cnn.com"])
        add("Shopping", "#F76B15", .distracting,
            apps: [],
            domains: ["amazon.com", "amazon.co.uk", "ebay.com", "ebay.co.uk", "etsy.com", "asos.com"])
        add("Utilities", "#8F8F8F", .neutral,
            apps: ["Finder", "System Settings", "1Password", "Activity Monitor", "App Store", "Raycast"],
            domains: [])

        return Config(categories: categories, rules: rules)
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return seconds > 0 ? "<1m" : "0m" }
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m)m" }
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

func formatClock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.up)))
    return String(format: "%d:%02d", total / 60, total % 60)
}

func formatScore(_ score: Double?) -> String {
    score.map { "\(Int($0.rounded()))" } ?? "–"
}

