import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // The label is always alive, so it's where app-level "open the dashboard" requests land.
        content.onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        let pomodoro = model.pomodoro
        switch pomodoro.phase {
        case .idle:
            if model.store.trackingPaused {
                Image(systemName: "pause.circle")
            } else {
                Image(nsImage: TempoGlyph.menuBar)
            }
        case .focus, .rest:
            Image(nsImage: TempoGlyph.progressImage(
                remaining: pomodoro.remaining, fraction: 1 - pomodoro.progress, isBreak: pomodoro.phase == .rest))
        }
    }
}

/// The popover: task, minute dial, one action, today's count. Everything else lives in the dashboard.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var task = ""

    var body: some View {
        let pomodoro = model.pomodoro
        let store = model.store
        let done = store.sessions(on: .now).filter(\.completed).count

        VStack(spacing: 0) {
            header(pomodoro.phase)
            Hairline()

            VStack(spacing: 20) {
                if pomodoro.phase == .idle {
                    TField(placeholder: "What are you working on?", text: $task, autofocus: true, onSubmit: start)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(pomodoro.phase == .rest ? "Up next" : "Working on")
                        Text(pomodoro.phase == .rest ? "Take a short break"
                             : (pomodoro.task.isEmpty ? "Untitled session" : pomodoro.task))
                            .font(.geist(14, .medium)).foregroundStyle(T.fg).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                }

                TimerDial()

                actionButton(pomodoro.phase)
            }
            .padding(20)

            footer(done: done, goal: store.config.dailyPomodoroGoal)
        }
        .frame(width: 320)
        .background(T.bg)
    }

    private func header(_ phase: Pomodoro.Phase) -> some View {
        HStack(spacing: 8) {
            TempoMark(size: 18)
            Text("Tempo").font(.geist(13, .semibold)).foregroundStyle(T.fg)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(phase == .focus ? T.blue : phase == .rest ? T.green : T.fg3).frame(width: 6, height: 6)
                Text(phase == .focus ? "Focusing" : phase == .rest ? "On break" : "Ready")
                    .font(.geist(12, .medium)).foregroundStyle(T.fg2)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .overlay(Capsule().strokeBorder(T.border))
            Menu {
                Button(model.store.trackingPaused ? "Resume tracking" : "Pause tracking") {
                    model.store.trackingPaused.toggle()
                    model.tracker.sample()
                }
                Button("Open Tempo", action: openDashboard)
                Divider()
                Button("Quit Tempo") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(T.fg2)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 48)
    }

    @ViewBuilder
    private func actionButton(_ phase: Pomodoro.Phase) -> some View {
        switch phase {
        case .idle:
            Button(action: start) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Start focus")
                    Spacer()
                    Kbd("↩")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TempoButtonStyle(kind: .primary, height: 38))
        case .focus:
            Button { model.pomodoro.stop() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill").font(.system(size: 9))
                    Text("End session early")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TempoButtonStyle(kind: .secondary, height: 38))
        case .rest:
            Button { model.pomodoro.skipBreak() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.end.fill").font(.system(size: 9))
                    Text("Skip break")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TempoButtonStyle(kind: .secondary, height: 38))
        }
    }

    private func footer(done: Int, goal: Int) -> some View {
        HStack(spacing: 10) {
            Text("Today").font(.geist(12)).foregroundStyle(T.fg2)
            HStack(spacing: 3) {
                ForEach(0..<max(goal, done), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < done ? T.fg : T.fill)
                        .frame(width: 8, height: 8)
                }
            }
            Text("\(done)/\(goal)").font(.mono(11, .medium)).foregroundStyle(T.fg2)
            Spacer()
            Button(action: openDashboard) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 11))
                    Text("Dashboard")
                }
            }
            .buttonStyle(TempoButtonStyle(kind: .ghost, height: 28))
            .keyboardShortcut("d")
            .help("Open Tempo (⌘D)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 46)
        .background(T.subtle)
        .overlay(alignment: .top) { Hairline() }
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func start() {
        guard model.pomodoro.phase == .idle else { return }
        model.pomodoro.startFocus(task: task)
        task = ""
    }
}

/// A 60-minute dial: one tick per minute, lit ticks are the minutes remaining (like a kitchen timer).
private struct TimerDial: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro
        let phase = pomodoro.phase
        let store = model.store
        let seconds = phase == .idle ? TimeInterval(store.config.focusMinutes * 60) : pomodoro.remaining
        let litTicks = min(60, Int((seconds / 60).rounded(.up)))
        let tint = phase == .rest ? T.green : phase == .focus ? T.fg : T.fg2

        ZStack {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 1
                for i in 0..<60 {
                    let major = i % 5 == 0
                    let color: Color = i < litTicks ? tint : (major ? T.borderStrong : T.fill)
                    let style = StrokeStyle(lineWidth: major ? 2.2 : 1.6, lineCap: .round)
                    ctx.stroke(Self.tick(i, center: center, radius: radius, length: major ? 11 : 7),
                               with: .color(color), style: style)
                }
            }

            VStack(spacing: 6) {
                Eyebrow(phase == .focus ? "Focus" : phase == .rest ? "Break" : "Session")
                Text(formatClock(seconds))
                    .font(.geist(50, .medium))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(T.fg)
                    .contentTransition(.numericText(countsDown: true))
                Text(caption(phase))
                    .font(.mono(11))
                    .foregroundStyle(T.fg3)
                    .frame(height: 14)
            }
        }
        .frame(width: 210, height: 210)
        .animation(.easeOut(duration: 0.25), value: litTicks)
    }

    private static func tick(_ index: Int, center: CGPoint, radius: CGFloat, length: CGFloat) -> Path {
        let angle = CGFloat(index) / 60 * 2 * .pi - .pi / 2
        let dx = cos(angle), dy = sin(angle)
        var path = Path()
        path.move(to: CGPoint(x: center.x + dx * (radius - length), y: center.y + dy * (radius - length)))
        path.addLine(to: CGPoint(x: center.x + dx * radius, y: center.y + dy * radius))
        return path
    }

    private func caption(_ phase: Pomodoro.Phase) -> String {
        let pomodoro = model.pomodoro
        let end = pomodoro.endDate?.formatted(date: .omitted, time: .shortened) ?? ""
        switch phase {
        case .idle:
            return "\(model.store.config.focusMinutes) min · \(model.store.config.breakMinutes) min break"
        case .focus:
            guard let start = pomodoro.startDate else { return "" }
            let score = model.store.summary(in: DateInterval(start: start, end: max(start, pomodoro.now))).score
            return score.map { "ends \(end) · score \(Int($0.rounded()))" } ?? "ends \(end)"
        case .rest:
            return "back at \(end)"
        }
    }
}
