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
            if pomodoro.needsAttention {
                // Break finished: stays until the popover is opened.
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                    Text("Ready")
                }
            } else if model.store.trackingPaused {
                Image(systemName: "pause.circle")
            } else {
                Image(nsImage: TempoGlyph.menuBar)
            }
        case .focus:
            HStack(spacing: 4) {
                Image(nsImage: TempoGlyph.menuBar)
                Text(formatClock(pomodoro.remaining)).monospacedDigit()
            }
        case .breakReady:
            HStack(spacing: 4) {
                Image(systemName: pomodoro.needsAttention ? "checkmark.circle.fill" : "cup.and.saucer")
                Text(pomodoro.needsAttention ? "Done" : "Break")
            }
        case .rest:
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer")
                Text(formatClock(pomodoro.remaining)).monospacedDigit()
            }
        }
    }
}

/// The popover: task, minute dial, one action, today's count. Everything else lives in the dashboard.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var task = ""
    @State private var window: NSWindow?

    var body: some View {
        let pomodoro = model.pomodoro
        let store = model.store
        let done = store.sessions(on: .now).filter(\.completed).count

        VStack(spacing: 0) {
            header(pomodoro.phase)
            Hairline()

            VStack(spacing: 20) {
                topSection(pomodoro)
                TimerDial()
                actionButtons(pomodoro.phase)
            }
            .padding(20)

            footer(done: done, goal: store.config.dailyPomodoroGoal)
        }
        .frame(width: 320)
        .background(T.bg)
        // Opening the popover acknowledges a finished session/break.
        .background { WindowReader(window: $window) }
        .onAppear { pomodoro.acknowledge() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window, note.object as? NSWindow === window { pomodoro.acknowledge() }
        }
    }

    @ViewBuilder
    private func topSection(_ pomodoro: Pomodoro) -> some View {
        switch pomodoro.phase {
        case .idle:
            TField(placeholder: "What are you working on?", text: $task, autofocus: true, onSubmit: primaryAction)
        case .focus:
            label(eyebrow: "Working on", text: pomodoro.task.isEmpty ? "Untitled session" : pomodoro.task)
        case .breakReady:
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(T.green, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session complete").font(.geist(14, .semibold)).foregroundStyle(T.fg)
                    Text(completedDetail(pomodoro))
                        .font(.geist(12)).foregroundStyle(T.fg2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        case .rest:
            label(eyebrow: "Break", text: "Step away from the screen")
        }
    }

    private func label(eyebrow: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(eyebrow)
            Text(text).font(.geist(14, .medium)).foregroundStyle(T.fg).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func completedDetail(_ pomodoro: Pomodoro) -> String {
        let name = pomodoro.task.isEmpty ? "Focus session" : pomodoro.task
        guard let session = pomodoro.lastSession, let score = model.store.score(for: session) else { return name }
        return "\(name) · focus score \(Int(score.rounded()))"
    }

    private func header(_ phase: Pomodoro.Phase) -> some View {
        let (dot, text): (Color, String) = switch phase {
        case .idle: (T.fg3, "Ready")
        case .focus: (T.blue, "Focusing")
        case .breakReady: (T.green, "Break time")
        case .rest: (T.green, "On break")
        }
        return HStack(spacing: 8) {
            TempoMark(size: 18)
            Text("Tempo").font(.geist(13, .semibold)).foregroundStyle(T.fg)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(text).font(.geist(12, .medium)).foregroundStyle(T.fg2)
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
                Button("Quit Tempo (stops tracking)") { AppDelegate.quit() }
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
    private func actionButtons(_ phase: Pomodoro.Phase) -> some View {
        switch phase {
        case .idle:
            Button(action: primaryAction) {
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
        case .breakReady:
            VStack(spacing: 8) {
                Button(action: primaryAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 11))
                        Text("Start \(model.store.config.breakMinutes) min break")
                        Spacer()
                        Kbd("↩")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoButtonStyle(kind: .success, height: 38))
                .keyboardShortcut(.defaultAction)
                Button("Skip break") { model.pomodoro.skipBreak() }
                    .buttonStyle(TempoButtonStyle(kind: .ghost, height: 26))
            }
        case .rest:
            Button { model.pomodoro.skipBreak() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.end.fill").font(.system(size: 9))
                    Text("End break early")
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

    /// Return key / main button: start focus when idle, start the break when one is waiting.
    private func primaryAction() {
        switch model.pomodoro.phase {
        case .idle:
            model.pomodoro.startFocus(task: task)
            task = ""
        case .breakReady:
            model.pomodoro.startBreak()
        case .focus, .rest:
            break
        }
    }
}

/// A 60-minute dial: one tick per minute, lit ticks are the minutes remaining (like a kitchen timer).
private struct TimerDial: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro
        let phase = pomodoro.phase
        let config = model.store.config
        let seconds: TimeInterval = switch phase {
        case .idle: TimeInterval(config.focusMinutes * 60)
        case .breakReady: TimeInterval(config.breakMinutes * 60)
        case .focus, .rest: pomodoro.remaining
        }
        let litTicks = min(60, Int((seconds / 60).rounded(.up)))
        let tint: Color = switch phase {
        case .idle: T.fg2
        case .focus: T.fg
        case .breakReady, .rest: T.green
        }

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
                Eyebrow(phase == .focus ? "Focus" : phase == .idle ? "Session" : "Break")
                Text(formatClock(seconds))
                    .font(.geist(50, .medium))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(phase == .breakReady || phase == .rest ? T.green : T.fg)
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
        case .breakReady:
            return "ready when you are"
        case .rest:
            return "back at \(end)"
        }
    }
}
