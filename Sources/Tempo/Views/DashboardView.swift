import Charts
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case day = "Overview"
    case trends = "Trends"
    case pomodoros = "Focus"
    case categories = "Categories"
    case settings = "Settings"

    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var section: DashboardSection = .day

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader()
            TabBar(selection: $section)
            ScrollView {
                Group {
                    switch section {
                    case .day: DayView()
                    case .trends: TrendsView()
                    case .pomodoros: PomodorosView()
                    case .categories: CategoriesView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: 1120)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .background(T.bg)
        }
        .background(T.bg)
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 900, minHeight: 640)
        .background(WindowChrome())
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

private struct DashboardHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro
        HStack(spacing: 10) {
            TempoMark(size: 20)
            Text("Tempo").font(.geist(15, .semibold)).foregroundStyle(T.fg)
            Text("/").font(.geist(18, .light)).foregroundStyle(T.borderStrong)
            Text(NSFullUserName().split(separator: " ").first.map(String.init) ?? "Personal")
                .font(.geist(14)).foregroundStyle(T.fg2)
            Text("Local").font(.mono(10, .medium)).foregroundStyle(T.fg2)
                .padding(.horizontal, 6).frame(height: 18)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(T.border))
            Spacer()
            switch pomodoro.phase {
            case .idle:
                Button {
                    pomodoro.startFocus(task: "")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("Start focus")
                    }
                }
                .buttonStyle(.primary)
            case .focus, .rest:
                HStack(spacing: 8) {
                    StatusDot(color: pomodoro.phase == .focus ? T.blue : T.green, size: 6)
                    Text(pomodoro.phase == .focus ? (pomodoro.task.isEmpty ? "Focusing" : pomodoro.task) : "Break")
                        .font(.geist(13, .medium)).foregroundStyle(T.fg).lineLimit(1)
                    Text(formatClock(pomodoro.remaining)).font(.mono(13, .medium)).foregroundStyle(T.fg2)
                        .monospacedDigit()
                    Button(pomodoro.phase == .focus ? "Stop" : "Skip") {
                        pomodoro.phase == .focus ? pomodoro.stop() : pomodoro.skipBreak()
                    }
                    .buttonStyle(TempoButtonStyle(kind: .secondary, height: 26))
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(T.border))
            }
        }
        .padding(.leading, 84) // traffic lights
        .padding(.trailing, 20)
        .frame(height: 52)
        .background(T.bg)
    }
}

private struct TabBar: View {
    @Binding var selection: DashboardSection
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardSection.allCases) { section in
                TabItem(title: section.rawValue, selected: selection == section, namespace: underline) {
                    withAnimation(.easeOut(duration: 0.18)) { selection = section }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(T.bg)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private struct TabItem: View {
        let title: String
        let selected: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.geist(13, selected ? .medium : .regular))
                    .foregroundStyle(selected || hovering ? T.fg : T.fg2)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(hovering ? T.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                if selected {
                    T.fg.frame(height: 2).padding(.horizontal, 8)
                        .matchedGeometryEffect(id: "underline", in: namespace)
                }
            }
        }
    }
}

/// Transparent, 52pt unified title bar so the traffic lights sit centred in our header.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            if window.toolbar == nil {
                window.toolbar = NSToolbar()
                window.toolbarStyle = .unified
            }
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Overview (day)

struct DayView: View {
    @Environment(AppModel.self) private var model
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var showAllItems = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        let store = model.store
        let summary = store.summary(for: day)
        let sessions = store.sessions(on: day).sorted { $0.start > $1.start }
        let completed = sessions.filter(\.completed)
        let sessionScores = completed.compactMap { store.score(for: $0) }
        let avgSessionScore = sessionScores.isEmpty ? nil : sessionScores.reduce(0, +) / Double(sessionScores.count)
        let yesterday = store.summary(for: Calendar.current.date(byAdding: .day, value: -1, to: day)!)
        let hourly = hourlyBreakdown(store.segments(on: day), categorizer: store.categorizer)

        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                title: isToday ? "Today" : day.formatted(.dateTime.weekday(.wide)),
                subtitle: day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
            ) {
                DayNavigator(day: $day)
            }

            MetricStrip {
                Metric(label: "Productivity score", value: formatScore(summary.score), unit: "/100",
                       detail: ScoreStatus(summary.score).label,
                       delta: summary.score.flatMap { s in yesterday.score.map { s - $0 } },
                       dot: ScoreStatus(summary.score).color)
                Metric(label: "Time tracked", value: formatDuration(summary.total),
                       detail: "\(formatDuration(summary.seconds(.productive))) productive")
                Metric(label: "Focus sessions", value: "\(completed.count)", unit: "/\(store.config.dailyPomodoroGoal)",
                       detail: sessions.count > completed.count
                           ? "\(sessions.count - completed.count) stopped early" : "daily goal")
                Metric(label: "Session focus", value: formatScore(avgSessionScore), unit: avgSessionScore == nil ? nil : "/100",
                       detail: "avg score during sessions", dot: ScoreStatus(avgSessionScore).color)
            }

            Panel(title: "Activity", subtitle: "Minutes per hour, split by productivity") {
                ProductivityLegend()
            } content: {
                Chart(hourly) { bucket in
                    BarMark(x: .value("Hour", bucket.hour), y: .value("Minutes", bucket.minutes), width: .fixed(16))
                        .foregroundStyle(by: .value("Type", bucket.productivity.label))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(domain: Productivity.allCases.map(\.label),
                                           range: Productivity.allCases.map(\.tint))
                .chartLegend(.hidden)
                .chartXScale(domain: -0.6...23.6)
                .chartYScale(domain: 0...60)
                .chartXAxis { hourAxis() }
                .chartYAxis { valueAxis([0, 15, 30, 45, 60]) }
                .frame(height: 200)
            }

            HStack(alignment: .top, spacing: 16) {
                Panel(title: "Categories", subtitle: "\(summary.categories.count) active") {
                    if summary.categories.isEmpty {
                        EmptyState(icon: "square.grid.2x2", title: "No activity",
                                   message: "Tempo records the app in front while you're at your Mac.")
                    } else {
                        CategoryBreakdown(summary: summary)
                    }
                }
                .frame(maxWidth: .infinity)

                Panel(title: "Focus sessions", subtitle: sessions.isEmpty ? nil : "\(completed.count) completed",
                      padded: false) {
                    if sessions.isEmpty {
                        EmptyState(icon: "timer", title: "No sessions",
                                   message: "Start a focus session from the menu bar or the header.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sessions) { session in
                                Hairline()
                                SessionRow(session: session, compact: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Panel(title: "Apps & websites", subtitle: "\(summary.items.count) tracked", padded: false) {
                if summary.items.isEmpty {
                    EmptyState(icon: "macwindow", title: "Nothing yet", message: "Apps and sites you use will appear here.")
                } else {
                    ItemTable(items: Array(summary.items.prefix(showAllItems ? 500 : 12)), total: summary.total)
                    if summary.items.count > 12 {
                        Hairline()
                        Button(showAllItems ? "Show less" : "Show all \(summary.items.count)") {
                            withAnimation { showAllItems.toggle() }
                        }
                        .buttonStyle(.ghost)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                }
            }
        }
    }
}

private struct DayNavigator: View {
    @Binding var day: Date

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        HStack(spacing: 0) {
            navButton("chevron.left") { shift(-1) }
            Hairline(vertical: true)
            Button("Today") { day = Calendar.current.startOfDay(for: .now) }
                .buttonStyle(TempoButtonStyle(kind: .ghost, height: 30))
                .disabled(isToday)
                .padding(.horizontal, 2)
            Hairline(vertical: true)
            navButton("chevron.right") { shift(1) }.disabled(isToday)
        }
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.border))
        .fixedSize()
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(T.fg2)
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day)!
    }
}

struct CategoryBreakdown: View {
    let summary: Summary
    var limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(summary.categories) { row in
                        RoundedRectangle(cornerRadius: 2).fill(row.color)
                            .frame(width: max(2, (geo.size.width - CGFloat(summary.categories.count) * 2)
                                                * row.seconds / max(1, summary.total)))
                    }
                }
            }
            .frame(height: 8)

            VStack(spacing: 2) {
                let top = summary.categories.first?.seconds ?? 1
                ForEach(summary.categories.prefix(limit)) { row in
                    BarRow(fraction: row.seconds / top) {
                        HStack(spacing: 8) {
                            CategoryDot(category: row.category)
                            Text(row.name).font(.geist(13)).foregroundStyle(T.fg).lineLimit(1)
                            Text(row.productivity.label.lowercased())
                                .font(.mono(10)).foregroundStyle(row.productivity.tint)
                        }
                    } trailing: {
                        Text(String(format: "%.0f%%", row.seconds / max(1, summary.total) * 100))
                            .font(.mono(11)).foregroundStyle(T.fg3)
                        Text(formatDuration(row.seconds)).font(.mono(12)).foregroundStyle(T.fg)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct ItemTable: View {
    let items: [ItemTotal]
    let total: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow("Name")
                Spacer()
                Eyebrow("Category").frame(width: 170, alignment: .leading)
                Eyebrow("Time").frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: 34)
            .background(T.subtle)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }

            let top = items.first?.seconds ?? 1
            ForEach(items) { item in
                ItemRowView(item: item, fraction: item.seconds / max(1, top))
                if item.id != items.last?.id { Hairline().padding(.leading, 52) }
            }
        }
    }
}

private struct ItemRowView: View {
    let item: ItemTotal
    let fraction: Double
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ItemAvatar(key: item.key)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.key.value).font(.geist(13, .medium)).foregroundStyle(T.fg).lineLimit(1)
                Text(item.key.kind == .domain ? item.app : "Application")
                    .font(.geist(12)).foregroundStyle(T.fg3)
            }
            Spacer(minLength: 16)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.fill)
                    Capsule().fill(item.category?.color ?? T.fg3).frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(width: 110, height: 4)
            .padding(.trailing, 12)
            AssignMenu(item: item.key, current: item.category)
                .frame(width: 170, alignment: .leading)
            Text(formatDuration(item.seconds)).font(.mono(12)).foregroundStyle(T.fg)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(hovering ? T.subtle : .clear)
        .onHover { hovering = $0 }
    }
}

/// Deployment-list style row for a pomodoro session.
struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: PomodoroSession
    var compact = false
    @State private var hovering = false

    var body: some View {
        let store = model.store
        let score = store.score(for: session)
        let top = store.summary(in: session.interval).categories.first
        let minutes = Int(session.end.timeIntervalSince(session.start) / 60)

        HStack(spacing: 14) {
            HStack(spacing: 8) {
                StatusDot(color: session.completed ? T.green : T.fg3, size: 6)
                if !compact {
                    Text(session.completed ? "Completed" : "Stopped")
                        .font(.geist(13)).foregroundStyle(T.fg2)
                }
            }
            .frame(width: compact ? 12 : 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.task.isEmpty ? "Untitled session" : session.task)
                    .font(.geist(13, .medium)).foregroundStyle(T.fg).lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.start.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("\(minutes)m")
                    if let top {
                        Text("·")
                        CategoryDot(category: top.category, size: 6)
                        Text(top.name).lineLimit(1)
                    }
                }
                .font(.mono(11)).foregroundStyle(T.fg3)
            }
            Spacer(minLength: 8)

            if hovering {
                Button {
                    store.deleteSession(session.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(TempoButtonStyle(kind: .ghost, height: 24))
                .help("Delete session")
            }

            ScoreMeter(score: score)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(hovering ? T.subtle : .clear)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete session", role: .destructive) { store.deleteSession(session.id) }
        }
    }
}

struct ScoreMeter: View {
    let score: Double?

    var body: some View {
        let status = ScoreStatus(score)
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.fill)
                    Capsule().fill(status.color).frame(width: geo.size.width * (score ?? 0) / 100)
                }
            }
            .frame(width: 44, height: 4)
            Text(formatScore(score)).font(.mono(12, .medium)).foregroundStyle(T.fg)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - Chart axes

@AxisContentBuilder
func hourAxis() -> some AxisContent {
    AxisMarks(values: Array(stride(from: 0, through: 21, by: 3))) { value in
        AxisValueLabel {
            Text(String(format: "%02d:00", value.as(Int.self) ?? 0)).font(.mono(10)).foregroundStyle(T.fg3)
        }
    }
}

@AxisContentBuilder
func valueAxis(_ values: [Double], suffix: String = "") -> some AxisContent {
    AxisMarks(position: .leading, values: values) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(T.border)
        AxisValueLabel {
            Text("\(Int(value.as(Double.self) ?? 0))\(suffix)").font(.mono(10)).foregroundStyle(T.fg3)
        }
    }
}

@AxisContentBuilder
func valueAxis(suffix: String = "") -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(T.border)
        AxisValueLabel {
            if let v = value.as(Double.self) {
                Text("\(v.formatted(.number.precision(.fractionLength(0...1))))\(suffix)")
                    .font(.mono(10)).foregroundStyle(T.fg3)
            }
        }
    }
}

@AxisContentBuilder
func dayAxis(_ days: Int) -> some AxisContent {
    AxisMarks(values: .stride(by: .day, count: max(1, days / 7))) { _ in
        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
            .font(.mono(10))
            .foregroundStyle(T.fg3)
    }
}
