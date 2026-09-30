import Charts
import SwiftUI

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 14

    var body: some View {
        let store = model.store
        let stats = store.dayStats(days: range)
        let previous = store.dayStats(
            days: range,
            endingOn: Calendar.current.date(byAdding: .day, value: -range, to: .now)!)
        let current = PeriodTotals(stats)
        let prior = PeriodTotals(previous)

        let hourRows = stats.flatMap { stat in
            Productivity.allCases.map { p in
                HoursRow(date: stat.date, productivity: p, hours: stat.summary.seconds(p) / 3600)
            }
        }
        let scored = stats.filter { $0.summary.score != nil }
        let pomodoroScored = stats.filter { $0.pomodoroScore != nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Trends").font(.title2.bold())
                    Spacer()
                    Picker("", selection: $range) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                HStack(spacing: 12) {
                    StatCard(title: "Avg productivity score", value: formatScore(current.avgScore),
                             detail: delta(current.avgScore, prior.avgScore, unit: " pts"),
                             tint: scoreColor(current.avgScore))
                    StatCard(title: "Productive time / day", value: formatDuration(current.productivePerDay),
                             detail: deltaDuration(current.productivePerDay, prior.productivePerDay))
                    StatCard(title: "Pomodoros completed", value: "\(current.pomodoros)",
                             detail: delta(Double(current.pomodoros), Double(prior.pomodoros), unit: ""))
                    StatCard(title: "Avg pomodoro score", value: formatScore(current.avgPomodoroScore),
                             detail: delta(current.avgPomodoroScore, prior.avgPomodoroScore, unit: " pts"),
                             tint: scoreColor(current.avgPomodoroScore))
                }

                Card(title: "Hours per day") {
                    Chart(hourRows) { row in
                        BarMark(x: .value("Day", row.date, unit: .day), y: .value("Hours", row.hours))
                            .foregroundStyle(by: .value("Type", row.productivity.label))
                    }
                    .chartForegroundStyleScale(domain: Productivity.allCases.map(\.label),
                                               range: Productivity.allCases.map(\.color))
                    .frame(height: 200)
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(title: "Productivity score") {
                        Chart {
                            ForEach(scored) { stat in
                                LineMark(x: .value("Day", stat.date, unit: .day),
                                         y: .value("Score", stat.summary.score ?? 0))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Day", stat.date, unit: .day),
                                          y: .value("Score", stat.summary.score ?? 0))
                                    .foregroundStyle(scoreColor(stat.summary.score))
                            }
                            if let avg = current.avgScore {
                                RuleMark(y: .value("Average", avg))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 180)
                    }
                    Card(title: "Pomodoros") {
                        Chart {
                            ForEach(stats) { stat in
                                BarMark(x: .value("Day", stat.date, unit: .day),
                                        y: .value("Completed", stat.pomodorosCompleted))
                                    .foregroundStyle(Color.accentColor.gradient)
                            }
                            RuleMark(y: .value("Goal", store.config.dailyPomodoroGoal))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.secondary)
                                .annotation(position: .top, alignment: .leading) {
                                    Text("goal").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        .frame(height: 180)
                    }
                }

                if !pomodoroScored.isEmpty {
                    Card(title: "Pomodoro focus score") {
                        Chart(pomodoroScored) { stat in
                            LineMark(x: .value("Day", stat.date, unit: .day),
                                     y: .value("Score", stat.pomodoroScore ?? 0))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Day", stat.date, unit: .day),
                                      y: .value("Score", stat.pomodoroScore ?? 0))
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 160)
                    }
                }

                Card(title: "Where the time went") {
                    let totals = store.summary(in: DateInterval(
                        start: stats.first?.date ?? .now, end: .now)).categories
                    if totals.isEmpty {
                        EmptyHint()
                    } else {
                        Chart(totals) { row in
                            BarMark(x: .value("Hours", row.seconds / 3600), y: .value("Category", row.name))
                                .foregroundStyle(row.color)
                                .annotation(position: .trailing) {
                                    Text(formatDuration(row.seconds)).font(.caption).foregroundStyle(.secondary)
                                }
                        }
                        .chartXAxisLabel("hours")
                        .frame(height: CGFloat(max(1, totals.count)) * 40 + 30)
                    }
                }
            }
            .padding(24)
        }
    }

    private func delta(_ now: Double?, _ before: Double?, unit: String) -> String {
        guard let now, let before else { return "no previous data" }
        let d = now - before
        let sign = d >= 0 ? "+" : "−"
        return "\(sign)\(Int(abs(d).rounded()))\(unit) vs previous \(range) days"
    }

    private func deltaDuration(_ now: TimeInterval, _ before: TimeInterval) -> String {
        guard before > 0 else { return "no previous data" }
        let d = now - before
        return "\(d >= 0 ? "+" : "−")\(formatDuration(abs(d))) vs previous \(range) days"
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
    var productivePerDay: TimeInterval = 0
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
        if !scored.isEmpty {
            // Weight each day's average by how many pomodoros it had.
            let weight = scored.reduce(0) { $0 + $1.pomodorosCompleted }
            avgPomodoroScore = scored.reduce(0.0) { $0 + ($1.pomodoroScore ?? 0) * Double($1.pomodorosCompleted) }
                / Double(max(1, weight))
        }
    }
}
