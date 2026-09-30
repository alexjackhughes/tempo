import Charts
import SwiftUI

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 14
    @State private var metric: TrendMetric = .score

    var body: some View {
        let store = model.store
        let stats = store.dayStats(days: range)
        let previous = store.dayStats(
            days: range, endingOn: Calendar.current.date(byAdding: .day, value: -range, to: .now)!)
        let current = PeriodTotals(stats)
        let prior = PeriodTotals(previous)
        let periodSummary = store.summary(in: DateInterval(start: stats.first?.date ?? .now, end: .now))

        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Trends", subtitle: "How your focus is changing over time") {
                Segmented(selection: $range, options: [(7, "7d"), (14, "14d"), (30, "30d"), (90, "90d")])
            }

            // Metric tabs + chart
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(TrendMetric.allCases) { m in
                        if m != TrendMetric.allCases.first { Hairline(vertical: true) }
                        MetricTab(metric: m, selected: metric == m, current: current, prior: prior) {
                            withAnimation(.easeOut(duration: 0.2)) { metric = m }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Hairline()
                TrendChart(metric: metric, stats: stats, range: range, goal: store.config.dailyPomodoroGoal,
                           average: current.value(metric))
                    .frame(height: 260)
                    .padding(20)
            }
            .background(T.surface)
            .clipShape(RoundedRectangle(cornerRadius: T.radius))
            .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.border))

            HStack(alignment: .top, spacing: 16) {
                Panel(title: "Hours by type", subtitle: "Productive, neutral and distracting time per day") {
                    ProductivityLegend()
                } content: {
                    let rows = stats.flatMap { stat in
                        Productivity.allCases.map {
                            HoursRow(date: stat.date, productivity: $0, hours: stat.summary.seconds($0) / 3600)
                        }
                    }
                    Chart(rows) { row in
                        BarMark(x: .value("Day", row.date, unit: .day), y: .value("Hours", row.hours))
                            .foregroundStyle(by: .value("Type", row.productivity.label))
                            .cornerRadius(2)
                    }
                    .chartForegroundStyleScale(domain: Productivity.allCases.map(\.label),
                                               range: Productivity.allCases.map(\.tint))
                    .chartLegend(.hidden)
                    .chartXAxis { dayAxis(range) }
                    .chartYAxis { valueAxis(suffix: "h") }
                    .frame(height: 220)
                }
                .frame(maxWidth: .infinity)

                Panel(title: "Top categories", subtitle: "Last \(range) days") {
                    if periodSummary.categories.isEmpty {
                        EmptyState(icon: "square.grid.2x2", title: "No data", message: "Nothing tracked in this period.")
                    } else {
                        CategoryBreakdown(summary: periodSummary, limit: 7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case score = "Productivity score"
    case productive = "Productive time"
    case pomodoros = "Focus sessions"
    case focus = "Session focus"

    var id: String { rawValue }
}

private struct MetricTab: View {
    let metric: TrendMetric
    let selected: Bool
    let current: PeriodTotals
    let prior: PeriodTotals
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.rawValue).font(.geist(13)).foregroundStyle(selected ? T.fg : T.fg2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(current.formatted(metric)).font(.geist(26, .semibold)).tracking(-0.9)
                        .foregroundStyle(T.fg)
                    Spacer(minLength: 0)
                    if let delta = current.delta(metric, from: prior) {
                        DeltaBadge(delta: delta.value, unit: delta.unit,
                                   text: metric == .productive ? formatDuration(abs(delta.value) * 60) : nil)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? T.subtle : hovering ? T.subtle.opacity(0.6) : .clear)
            .overlay(alignment: .bottom) {
                if selected { T.fg.frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct TrendChart: View {
    let metric: TrendMetric
    let stats: [DayStat]
    let range: Int
    let goal: Int
    let average: Double?

    var body: some View {
        switch metric {
        case .score, .focus:
            let points = stats.compactMap { stat -> (Date, Double)? in
                let value = metric == .score ? stat.summary.score : stat.pomodoroScore
                return value.map { (stat.date, $0) }
            }
            if points.isEmpty {
                EmptyState(icon: "chart.xyaxis.line", title: "Not enough data",
                           message: "Scores appear once Tempo has tracked some time.")
            } else {
                Chart {
                    ForEach(points, id: \.0) { date, value in
                        AreaMark(x: .value("Day", date, unit: .day), y: .value("Score", value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [T.blue.opacity(0.22), T.blue.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", date, unit: .day), y: .value("Score", value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(T.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let average {
                        RuleMark(y: .value("Average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(T.fg3)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("avg \(Int(average.rounded()))").font(.mono(10)).foregroundStyle(T.fg3)
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { dayAxis(range) }
                .chartYAxis { valueAxis([0, 25, 50, 75, 100]) }
            }

        case .productive:
            Chart(stats) { stat in
                BarMark(x: .value("Day", stat.date, unit: .day),
                        y: .value("Hours", stat.summary.seconds(.productive) / 3600))
                    .foregroundStyle(T.blue)
                    .cornerRadius(3)
            }
            .chartXAxis { dayAxis(range) }
            .chartYAxis { valueAxis(suffix: "h") }

        case .pomodoros:
            Chart {
                ForEach(stats) { stat in
                    BarMark(x: .value("Day", stat.date, unit: .day), y: .value("Sessions", stat.pomodorosCompleted))
                        .foregroundStyle(stat.pomodorosCompleted >= goal ? T.fg : T.fg3.opacity(0.6))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(T.green)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("goal \(goal)").font(.mono(10)).foregroundStyle(T.green)
                    }
            }
            .chartXAxis { dayAxis(range) }
            .chartYAxis { valueAxis() }
        }
    }
}

private struct HoursRow: Identifiable {
    let date: Date
    let productivity: Productivity
    let hours: Double
    var id: String { "\(date.timeIntervalSince1970)-\(productivity.rawValue)" }
}

private struct PeriodTotals {
    var avgScore: Double?
    var productivePerDay: TimeInterval?
    var pomodoros = 0
    var avgPomodoroScore: Double?

    init(_ stats: [DayStat]) {
        let active = stats.filter { $0.summary.total >= 60 }
        let total = active.reduce(0) { $0 + $1.summary.total }
        if total > 0 {
            let weighted = active.reduce(0.0) { acc, stat in
                acc + Productivity.allCases.reduce(0) { $0 + $1.weight * stat.summary.seconds($1) }
            }
            avgScore = weighted / total * 100
            productivePerDay = active.reduce(0) { $0 + $1.summary.seconds(.productive) } / Double(active.count)
        }
        pomodoros = stats.reduce(0) { $0 + $1.pomodorosCompleted }
        let scored = stats.filter { $0.pomodoroScore != nil }
        let weight = scored.reduce(0) { $0 + $1.pomodorosCompleted }
        if weight > 0 {
            avgPomodoroScore = scored.reduce(0.0) { $0 + ($1.pomodoroScore ?? 0) * Double($1.pomodorosCompleted) }
                / Double(weight)
        }
    }

    func value(_ metric: TrendMetric) -> Double? {
        switch metric {
        case .score: avgScore
        case .productive: productivePerDay
        case .pomodoros: Double(pomodoros)
        case .focus: avgPomodoroScore
        }
    }

    func formatted(_ metric: TrendMetric) -> String {
        switch metric {
        case .score, .focus: formatScore(value(metric))
        case .productive: productivePerDay.map { "\(formatDuration($0))/d" } ?? "–"
        case .pomodoros: "\(pomodoros)"
        }
    }

    func delta(_ metric: TrendMetric, from prior: PeriodTotals) -> (value: Double, unit: String)? {
        guard let now = value(metric), let before = prior.value(metric) else { return nil }
        if metric == .pomodoros, before == 0 { return nil }
        if metric == .productive { return ((now - before) / 60, "m") }
        return (now - before, "")
    }
}
