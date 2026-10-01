import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro
        switch pomodoro.phase {
        case .idle:
            if model.store.trackingPaused {
                Image(systemName: "pause.circle")
            } else {
                Image(nsImage: TempoGlyph.menuBar)
            }
        case .focus:
            HStack(spacing: 4) {
                Image(nsImage: TempoGlyph.menuBar)
                Text(formatClock(pomodoro.remaining)).monospacedDigit()
            }
        case .rest:
            HStack(spacing: 3) {
                Image(systemName: "cup.and.saucer")
                Text(formatClock(pomodoro.remaining)).monospacedDigit()
            }
        }
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let store = model.store
        let summary = store.summary(for: .now)
        let status = ScoreStatus(summary.score)

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                TempoMark(size: 16)
                Text("Tempo").font(.geist(14, .semibold)).foregroundStyle(T.fg)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(store.trackingPaused ? T.amber : T.green).frame(width: 6, height: 6)
                    Text(store.trackingPaused ? "Paused" : "Tracking")
                        .font(.geist(12)).foregroundStyle(T.fg2)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Hairline()

            // Today
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Today")
                    Spacer()
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.mono(11)).foregroundStyle(T.fg3)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(formatScore(summary.score))
                        .font(.geist(40, .semibold)).tracking(-1.6).foregroundStyle(T.fg)
                    Text("/100").font(.mono(12)).foregroundStyle(T.fg3).padding(.leading, 4)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            StatusDot(color: status.color, size: 6)
                            Text(status.label).font(.geist(13, .medium)).foregroundStyle(T.fg)
                        }
                        Text("\(formatDuration(summary.total)) tracked").font(.mono(11)).foregroundStyle(T.fg2)
                    }
                }
                ProductivityBar(summary: summary)
                ProductivityLegend(summary: summary)
            }
            .padding(16)
            Hairline()

            PomodoroPanel().padding(16)
            Hairline()

            // Categories
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Top categories").padding(.bottom, 4)
                if summary.categories.isEmpty {
                    Text("Nothing tracked yet today.").font(.geist(13)).foregroundStyle(T.fg3)
                        .padding(.vertical, 6)
                }
                let top = summary.categories.first?.seconds ?? 1
                ForEach(summary.categories.prefix(4)) { row in
                    BarRow(fraction: row.seconds / top) {
                        HStack(spacing: 8) {
                            CategoryDot(category: row.category)
                            Text(row.name).font(.geist(13)).foregroundStyle(T.fg)
                        }
                    } trailing: {
                        Text(formatDuration(row.seconds)).font(.mono(12)).foregroundStyle(T.fg2)
                    }
                    .frame(height: 30)
                }
            }
            .padding(16)

            // Footer
            HStack(spacing: 4) {
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 8) {
                        Text("Open dashboard")
                        Kbd("⌘D")
                    }
                }
                .buttonStyle(.ghost)
                .keyboardShortcut("d")
                Spacer()
                Button {
                    store.trackingPaused.toggle()
                    model.tracker.sample()
                } label: {
                    Image(systemName: store.trackingPaused ? "play.fill" : "pause.fill").font(.system(size: 11))
                }
                .buttonStyle(.ghost)
                .help(store.trackingPaused ? "Resume tracking" : "Pause tracking")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.ghost)
                .keyboardShortcut("q")
                .help("Quit Tempo")
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(T.subtle)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 340)
        .background(T.bg)
    }
}

struct PomodoroPanel: View {
    @Environment(AppModel.self) private var model
    @State private var task = ""

    var body: some View {
        let pomodoro = model.pomodoro
        let store = model.store
        let done = store.sessions(on: .now).filter(\.completed).count

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(pomodoro.phase == .rest ? "Break" : "Focus")
                Spacer()
                GoalTally(done: done, goal: store.config.dailyPomodoroGoal)
            }

            switch pomodoro.phase {
            case .idle:
                TField(placeholder: "What are you working on?", text: $task, autofocus: true, onSubmit: start)
                Button(action: start) {
                    HStack {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Start \(store.config.focusMinutes) min focus")
                        Spacer()
                        Kbd("↩")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoButtonStyle(kind: .primary, height: 36))

            case .focus:
                let live = pomodoro.startDate.map {
                    store.summary(in: DateInterval(start: $0, end: max($0, pomodoro.now)))
                } ?? Summary()
                let status = ScoreStatus(live.score)
                VStack(alignment: .leading, spacing: 10) {
                    Text(pomodoro.task.isEmpty ? "Untitled session" : pomodoro.task)
                        .font(.geist(14, .medium)).foregroundStyle(T.fg).lineLimit(1)
                    HStack(alignment: .lastTextBaseline) {
                        Text(formatClock(pomodoro.remaining))
                            .font(.mono(44, .medium)).tracking(-2).foregroundStyle(T.fg)
                            .contentTransition(.numericText(countsDown: true))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Focus score").font(.geist(11)).foregroundStyle(T.fg3)
                            HStack(spacing: 6) {
                                StatusDot(color: status.color, size: 6)
                                Text(formatScore(live.score)).font(.mono(15, .medium)).foregroundStyle(T.fg)
                            }
                        }
                    }
                    ProgressLine(progress: pomodoro.progress, tint: T.fg)
                    HStack {
                        Text("Ends \(pomodoro.endDate?.formatted(date: .omitted, time: .shortened) ?? "")")
                            .font(.mono(11)).foregroundStyle(T.fg3)
                        Spacer()
                        Button("Stop session") { pomodoro.stop() }.buttonStyle(TempoButtonStyle(kind: .secondary, height: 28))
                    }
                }

            case .rest:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step away for a few minutes.").font(.geist(14, .medium)).foregroundStyle(T.fg)
                    Text(formatClock(pomodoro.remaining))
                        .font(.mono(44, .medium)).tracking(-2).foregroundStyle(T.fg2)
                    ProgressLine(progress: pomodoro.progress, tint: T.green)
                    HStack {
                        Spacer()
                        Button("Skip break") { pomodoro.skipBreak() }
                            .buttonStyle(TempoButtonStyle(kind: .secondary, height: 28))
                    }
                }
            }
        }
    }

    private func start() {
        model.pomodoro.startFocus(task: task)
        task = ""
    }
}

struct ProgressLine: View {
    let progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(T.fill)
                Capsule().fill(tint).frame(width: max(3, geo.size.width * progress))
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 1), value: progress)
    }
}

/// Row of small squares showing completed pomodoros against the daily goal.
struct GoalTally: View {
    let done: Int
    let goal: Int

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<max(goal, done), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < done ? T.fg : T.fill)
                        .frame(width: 7, height: 7)
                }
            }
            Text("\(done)/\(goal)").font(.mono(11)).foregroundStyle(T.fg2)
        }
    }
}
