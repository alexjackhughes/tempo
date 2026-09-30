import Charts
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case day = "Day"
    case trends = "Trends"
    case pomodoros = "Pomodoros"
    case categories = "Categories"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .day: "calendar"
        case .trends: "chart.line.uptrend.xyaxis"
        case .pomodoros: "timer"
        case .categories: "tag"
        case .settings: "gearshape"
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var section: DashboardSection? = .day

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            switch section ?? .day {
            case .day: DayView()
            case .trends: TrendsView()
            case .pomodoros: PomodorosView()
            case .categories: CategoriesView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            // Show in the Dock / Cmd-Tab while the dashboard is open.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            model.store.flush()
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Day

struct DayView: View {
    @Environment(AppModel.self) private var model
    @State private var day = Calendar.current.startOfDay(for: .now)

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        let store = model.store
        let summary = store.summary(for: day)
        let sessions = store.sessions(on: day)
        let completed = sessions.filter(\.completed)
        let sessionScores = completed.compactMap { store.score(for: $0) }
        let avgSessionScore = sessionScores.isEmpty ? nil : sessionScores.reduce(0, +) / Double(sessionScores.count)
        let hourly = hourlyBreakdown(store.segments(on: day), categorizer: store.categorizer)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(isToday)
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title2.bold())
                    Spacer()
                    if !isToday {
                        Button("Today") { day = Calendar.current.startOfDay(for: .now) }
                    }
                }
                .buttonStyle(.borderless)

                HStack(spacing: 12) {
                    StatCard(title: "Productivity score", value: formatScore(summary.score),
                             detail: "0 = all distracting, 100 = all productive", tint: scoreColor(summary.score))
                    StatCard(title: "Time tracked", value: formatDuration(summary.total),
                             detail: "\(formatDuration(summary.seconds(.productive))) productive")
                    StatCard(title: "Pomodoros", value: "\(completed.count)",
                             detail: "goal \(store.config.dailyPomodoroGoal) · \(sessions.count - completed.count) stopped early")
                    StatCard(title: "Avg pomodoro score", value: formatScore(avgSessionScore),
                             detail: "focus quality during sessions", tint: scoreColor(avgSessionScore))
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Categories") {
                        if summary.categories.isEmpty {
                            EmptyHint()
                        } else {
                            HStack(alignment: .center, spacing: 20) {
                                Chart(summary.categories) { row in
                                    SectorMark(angle: .value("Time", row.seconds),
                                               innerRadius: .ratio(0.62), angularInset: 1)
                                        .foregroundStyle(row.color)
                                        .cornerRadius(3)
                                }
                                .frame(width: 170, height: 170)
                                VStack(alignment: .leading, spacing: 7) {
                                    ForEach(summary.categories) { row in
                                        HStack {
                                            Circle().fill(row.color).frame(width: 9, height: 9)
                                            Text(row.name)
                                            Spacer()
                                            Text(formatDuration(row.seconds)).monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Card(title: "Pomodoros") {
                        if sessions.isEmpty {
                            Text("No pomodoros this day.").foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(sessions) { SessionRow(session: $0, showDate: false) }
                            }
                        }
                    }
                    .frame(maxWidth: 360)
                }

                Card(title: "Through the day") {
                    Chart(hourly) { bucket in
                        BarMark(x: .value("Hour", bucket.hour), y: .value("Minutes", bucket.minutes), width: .fixed(22))
                            .foregroundStyle(by: .value("Type", bucket.productivity.label))
                    }
                    .chartForegroundStyleScale(domain: Productivity.allCases.map(\.label),
                                               range: Productivity.allCases.map(\.color))
                    .chartXScale(domain: 0...23)
                    .chartXAxis {
                        AxisMarks(values: Array(stride(from: 0, through: 23, by: 3))) { value in
                            AxisGridLine()
                            AxisValueLabel { Text("\(value.as(Int.self) ?? 0):00") }
                        }
                    }
                    .chartYAxisLabel("minutes")
                    .chartYScale(domain: 0...60)
                    .frame(height: 180)
                }

                Card(title: "Apps & websites") {
                    if summary.items.isEmpty {
                        EmptyHint()
                    } else {
                        ItemList(items: Array(summary.items.prefix(40)), total: summary.total)
                    }
                }
            }
            .padding(24)
        }
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day)!
    }
}

struct ItemList: View {
    let items: [ItemTotal]
    let total: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    ItemIcon(item: item)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.key.value).lineLimit(1)
                        if item.key.kind == .domain {
                            Text(item.app).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    GeometryReader { geo in
                        Capsule().fill(item.category?.color ?? Color.gray.opacity(0.45))
                            .frame(width: max(3, geo.size.width * item.seconds / max(1, items.first?.seconds ?? 1)))
                    }
                    .frame(width: 120, height: 6)
                    Text(formatDuration(item.seconds)).monospacedDigit().frame(width: 64, alignment: .trailing)
                    AssignMenu(item: item.key, current: item.category)
                        .frame(width: 170, alignment: .leading)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}

struct EmptyHint: View {
    var body: some View {
        Text("Nothing tracked yet — Tempo records whichever app is frontmost while you're active.")
            .foregroundStyle(.secondary)
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: PomodoroSession
    var showDate = true

    var body: some View {
        let store = model.store
        let score = store.score(for: session)
        let top = store.summary(in: session.interval).categories.first
        HStack(spacing: 10) {
            Image(systemName: session.completed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(session.completed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.task.isEmpty ? "Focus session" : session.task).lineLimit(1)
                Text(timeLabel + (top.map { " · mostly \($0.name)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(formatScore(score))
                .font(.system(.body, design: .rounded).bold())
                .foregroundStyle(scoreColor(score))
                .frame(width: 34, alignment: .trailing)
        }
        .contextMenu {
            Button("Delete session", role: .destructive) { store.deleteSession(session.id) }
        }
    }

    private var timeLabel: String {
        let time = session.start.formatted(showDate
            ? .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
            : .dateTime.hour().minute())
        let minutes = Int(session.end.timeIntervalSince(session.start) / 60)
        return "\(time) · \(minutes) min"
    }
}
