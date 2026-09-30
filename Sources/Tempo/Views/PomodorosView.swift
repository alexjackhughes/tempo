import Charts
import SwiftUI

struct PomodorosView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all

    enum Filter: Hashable { case all, completed, stopped }

    var body: some View {
        let store = model.store
        let all = store.sessions.sorted { $0.start > $1.start }
        let completed = all.filter(\.completed)
        let scores = completed.compactMap { store.score(for: $0) }
        let avg = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let thisWeek = completed.filter { $0.start >= weekAgo }.count
        let completionRate = all.isEmpty ? nil : Double(completed.count) / Double(all.count) * 100
        let byHour = hourlyScores(completed)
        let best = byHour.filter { $0.count >= 2 }.max { $0.score < $1.score }
        let focused = completed.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        let visible = all.filter {
            switch filter {
            case .all: true
            case .completed: $0.completed
            case .stopped: !$0.completed
            }
        }
        let grouped = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }

        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Focus", subtitle: "Every session, scored by what you actually did during it") {
                Button {
                    model.pomodoro.startFocus(task: "")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("New session")
                    }
                }
                .buttonStyle(.primary)
                .disabled(model.pomodoro.phase != .idle)
            }

            MetricStrip {
                Metric(label: "Completed", value: "\(completed.count)", detail: "\(formatDuration(focused)) focused")
                Metric(label: "Last 7 days", value: "\(thisWeek)",
                       detail: String(format: "%.1f per day", Double(thisWeek) / 7))
                Metric(label: "Completion rate", value: completionRate.map { "\(Int($0.rounded()))" } ?? "–",
                       unit: completionRate == nil ? nil : "%", detail: "finished vs. stopped early")
                Metric(label: "Avg focus score", value: formatScore(avg), unit: avg == nil ? nil : "/100",
                       detail: best.map { "sharpest around \(String(format: "%02d:00", $0.hour))" } ?? "needs more sessions",
                       dot: ScoreStatus(avg).color)
            }

            if !byHour.isEmpty {
                Panel(title: "Focus by time of day", subtitle: "Average session score by start hour") {
                    Chart(byHour) { row in
                        BarMark(x: .value("Hour", row.hour), y: .value("Score", row.score), width: .fixed(16))
                            .foregroundStyle(row.hour == best?.hour ? T.blue : T.fg3.opacity(0.45))
                            .cornerRadius(2)
                            .annotation(position: .top) {
                                Text("\(row.count)").font(.mono(9)).foregroundStyle(T.fg3)
                            }
                    }
                    .chartXScale(domain: -0.6...23.6)
                    .chartYScale(domain: 0...100)
                    .chartXAxis { hourAxis() }
                    .chartYAxis { valueAxis([0, 50, 100]) }
                    .frame(height: 160)
                }
            }

            Panel(padded: false) {
                HStack {
                    Segmented(selection: $filter, options: [(.all, "All"), (.completed, "Completed"), (.stopped, "Stopped")],
                              compact: true)
                    Spacer()
                    Text("\(visible.count) sessions").font(.mono(11)).foregroundStyle(T.fg3)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                if visible.isEmpty {
                    Hairline()
                    EmptyState(icon: "timer", title: "No sessions yet",
                               message: "Start one from the menu bar. Tempo scores each session from the apps and sites you used during it.")
                }

                ForEach(grouped, id: \.key) { day, sessions in
                    let dayScores = sessions.filter(\.completed).compactMap { store.score(for: $0) }
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                            .font(.mono(11, .medium)).foregroundStyle(T.fg2)
                        Spacer()
                        Text("\(sessions.filter(\.completed).count) done")
                        if !dayScores.isEmpty {
                            Text("·")
                            Text("avg \(Int((dayScores.reduce(0, +) / Double(dayScores.count)).rounded()))")
                        }
                    }
                    .font(.mono(11)).foregroundStyle(T.fg3)
                    .padding(.horizontal, 20)
                    .frame(height: 32)
                    .background(T.subtle)
                    .overlay(alignment: .top) { Hairline() }
                    .overlay(alignment: .bottom) { Hairline() }

                    ForEach(sessions) { session in
                        SessionRow(session: session)
                        if session.id != sessions.last?.id { Hairline() }
                    }
                }
            }
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
