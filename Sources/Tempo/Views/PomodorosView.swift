import Charts
import SwiftUI

struct PomodorosView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let sessions = store.sessions.sorted { $0.start > $1.start }
        let completed = sessions.filter(\.completed)
        let scores = completed.compactMap { store.score(for: $0) }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let thisWeek = completed.filter { $0.start >= weekAgo }.count
        let completionRate = sessions.isEmpty ? nil : Double(completed.count) / Double(sessions.count) * 100
        let byHour = hourlyScores(completed)
        let best = byHour.filter { $0.count >= 2 }.max { $0.score < $1.score }
        let grouped = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pomodoros").font(.title2.bold())

                HStack(spacing: 12) {
                    StatCard(title: "Completed (all time)", value: "\(completed.count)",
                             detail: "\(formatDuration(completed.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) })) focused")
                    StatCard(title: "Last 7 days", value: "\(thisWeek)",
                             detail: "\(String(format: "%.1f", Double(thisWeek) / 7)) per day")
                    StatCard(title: "Completion rate", value: completionRate.map { "\(Int($0.rounded()))%" } ?? "–",
                             detail: "finished vs. stopped early")
                    let avg = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
                    StatCard(title: "Avg focus score", value: formatScore(avg),
                             detail: best.map { "best around \($0.hour):00" } ?? "needs more sessions",
                             tint: scoreColor(avg))
                }

                if !byHour.isEmpty {
                    Card(title: "Focus score by time of day") {
                        Chart(byHour) { row in
                            BarMark(x: .value("Hour", row.hour), y: .value("Score", row.score), width: .fixed(22))
                                .foregroundStyle(scoreColor(row.score).gradient)
                                .annotation(position: .top) {
                                    Text("\(row.count)").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        .chartXScale(domain: 0...23)
                        .chartYScale(domain: 0...100)
                        .chartXAxis {
                            AxisMarks(values: Array(stride(from: 0, through: 23, by: 3))) { value in
                                AxisGridLine()
                                AxisValueLabel { Text("\(value.as(Int.self) ?? 0):00") }
                            }
                        }
                        .frame(height: 160)
                        Text("Numbers above bars are session counts. Right-click a session below to delete it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if sessions.isEmpty {
                    Card {
                        Text("No pomodoros yet. Start one from the menu bar — Tempo will score how focused each session was based on the apps and sites you used during it.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(grouped, id: \.key) { day, daySessions in
                    Card(title: day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                        VStack(spacing: 8) {
                            ForEach(daySessions) { SessionRow(session: $0, showDate: false) }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func hourlyScores(_ sessions: [PomodoroSession]) -> [HourScore] {
        var buckets: [Int: [Double]] = [:]
        for session in sessions {
            guard let score = model.store.score(for: session) else { continue }
            buckets[Calendar.current.component(.hour, from: session.start), default: []].append(score)
        }
        return buckets.map { HourScore(hour: $0.key, score: $0.value.reduce(0, +) / Double($0.value.count),
                                       count: $0.value.count) }
            .sorted { $0.hour < $1.hour }
    }
}

private struct HourScore: Identifiable {
    let hour: Int
    let score: Double
    let count: Int
    var id: Int { hour }
}
