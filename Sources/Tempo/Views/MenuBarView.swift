import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro
        switch pomodoro.phase {
        case .idle:
            Image(systemName: model.store.trackingPaused ? "pause.circle" : "timer")
        case .focus:
            HStack(spacing: 3) {
                Image(systemName: "brain.head.profile")
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
        let completedToday = store.sessions(on: .now).filter(\.completed).count

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ScoreRing(score: summary.score, size: 58, lineWidth: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today").font(.headline)
                    Text("\(formatDuration(summary.total)) tracked")
                        .foregroundStyle(.secondary)
                    Text("\(completedToday)/\(store.config.dailyPomodoroGoal) pomodoros")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Spacer()
            }
            ProductivityBar(summary: summary)

            Divider()
            PomodoroPanel()
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.categories.prefix(5)) { row in
                    HStack {
                        Circle().fill(row.color).frame(width: 8, height: 8)
                        Text(row.name)
                        Spacer()
                        Text(formatDuration(row.seconds)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
                if summary.categories.isEmpty {
                    Text("No activity yet today.").font(.callout).foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Dashboard", systemImage: "chart.bar.xaxis")
                }
                Spacer()
                Button {
                    store.trackingPaused.toggle()
                    model.tracker.sample()
                } label: {
                    Image(systemName: store.trackingPaused ? "play.fill" : "pause.fill")
                }
                .help(store.trackingPaused ? "Resume tracking" : "Pause tracking")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Tempo")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
    }
}

struct PomodoroPanel: View {
    @Environment(AppModel.self) private var model
    @State private var task = ""

    var body: some View {
        let pomodoro = model.pomodoro
        switch pomodoro.phase {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                TextField("What are you focusing on?", text: $task)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(start)
                Button(action: start) {
                    Label("Start \(model.store.config.focusMinutes) min focus", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .focus:
            let live = pomodoro.startDate.map {
                model.store.summary(in: DateInterval(start: $0, end: max($0, pomodoro.now)))
            } ?? Summary()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(pomodoro.task.isEmpty ? "Focusing" : pomodoro.task)
                        .font(.headline).lineLimit(1)
                    Spacer()
                    Text(formatClock(pomodoro.remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                ProgressView(value: pomodoro.progress).tint(.accentColor)
                HStack {
                    Text("Session focus score").foregroundStyle(.secondary)
                    Text(formatScore(live.score)).foregroundStyle(scoreColor(live.score)).bold()
                    Spacer()
                    Button("Stop", role: .destructive) { pomodoro.stop() }
                }
                .font(.callout)
            }
        case .rest:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Break", systemImage: "cup.and.saucer.fill").font(.headline)
                    Spacer()
                    Text(formatClock(pomodoro.remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                ProgressView(value: pomodoro.progress).tint(.green)
                HStack {
                    Spacer()
                    Button("Skip break") { pomodoro.skipBreak() }
                }
                .font(.callout)
            }
        }
    }

    private func start() {
        model.pomodoro.startFocus(task: task)
        task = ""
    }
}
