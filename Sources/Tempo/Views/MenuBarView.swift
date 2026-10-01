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

/// The popover: task, timer ring, today's count. Everything else lives in the dashboard.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var task = ""

    var body: some View {
        let pomodoro = model.pomodoro
        let store = model.store
        let done = store.sessions(on: .now).filter(\.completed).count

        VStack(spacing: 0) {
            // Task
            Group {
                if pomodoro.phase == .idle {
                    TaskField(text: $task, onSubmit: start)
                } else {
                    Text(pomodoro.phase == .rest ? "Break" : (pomodoro.task.isEmpty ? "Focusing" : pomodoro.task))
                        .font(.geist(17, .medium))
                        .foregroundStyle(T.fg)
                        .lineLimit(1)
                }
            }
            .frame(height: 30)
            .padding(.horizontal, 24)
            .padding(.top, 22)

            TimerRing(onStart: start)
                .padding(.vertical, 22)

            // Footer
            HStack {
                Button {
                    openDashboard()
                } label: {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 14))
                }
                .buttonStyle(TempoButtonStyle(kind: .ghost, height: 30))
                .keyboardShortcut("d")
                .help("Open Tempo (⌘D)")

                Spacer()

                HStack(spacing: 6) {
                    Text("Today").foregroundStyle(T.fg2)
                    Text("\(done)").foregroundStyle(T.fg)
                    Text("/ \(store.config.dailyPomodoroGoal)").foregroundStyle(T.fg3)
                }
                .font(.geist(15, .medium))
                .monospacedDigit()

                Spacer()

                Menu {
                    Button(store.trackingPaused ? "Resume tracking" : "Pause tracking") {
                        store.trackingPaused.toggle()
                        model.tracker.sample()
                    }
                    Button("Open Tempo", action: openDashboard)
                    Divider()
                    Button("Quit Tempo") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(T.fg2)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 300)
        .background(T.bg)
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

/// Borderless, centred task input that focuses itself whenever the popover opens.
private struct TaskField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @FocusState private var focused: Bool
    @State private var window: NSWindow?

    var body: some View {
        TextField("", text: $text, prompt: Text("What are you focusing on?").foregroundStyle(T.fg3))
            .textFieldStyle(.plain)
            .font(.geist(17))
            .foregroundStyle(T.fg)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit(onSubmit)
            .background { WindowReader(window: $window) }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                if let window, note.object as? NSWindow === window { focused = true }
            }
            .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

private struct TimerRing: View {
    @Environment(AppModel.self) private var model
    let onStart: () -> Void

    private let diameter: CGFloat = 220
    private let lineWidth: CGFloat = 5

    var body: some View {
        let pomodoro = model.pomodoro
        let phase = pomodoro.phase
        let fraction = phase == .idle ? 1 : max(0, 1 - pomodoro.progress)
        let tint = phase == .rest ? T.green : T.fg
        let seconds = phase == .idle ? TimeInterval(model.store.config.focusMinutes * 60) : pomodoro.remaining

        ZStack {
            Circle().stroke(T.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Knob at the leading edge of the remaining time.
            Circle()
                .fill(T.bg)
                .overlay(Circle().strokeBorder(tint, lineWidth: lineWidth - 1))
                .frame(width: 20, height: 20)
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(360 * fraction))

            VStack(spacing: 10) {
                Text(formatClock(seconds))
                    .font(.geist(58))
                    .tracking(-2.5)
                    .monospacedDigit()
                    .foregroundStyle(phase == .rest ? T.fg2 : T.fg)
                    .contentTransition(.numericText(countsDown: true))

                Button {
                    switch phase {
                    case .idle: onStart()
                    case .focus: pomodoro.stop()
                    case .rest: pomodoro.skipBreak()
                    }
                } label: {
                    Image(systemName: phase == .idle ? "play.fill" : phase == .focus ? "stop.fill" : "forward.end.fill")
                        .font(.system(size: phase == .idle ? 18 : 15))
                        .offset(x: phase == .idle ? 2 : 0)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(phase == .idle ? T.inverted : T.fg)
                        .background(phase == .idle ? T.fg : T.hover, in: Circle())
                        .overlay(Circle().strokeBorder(phase == .idle ? .clear : T.border))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(phase == .idle ? "Start (↩)" : phase == .focus ? "Stop session" : "Skip break")

                Text(caption(for: phase))
                    .font(.mono(11))
                    .foregroundStyle(T.fg3)
                    .frame(height: 14)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 1), value: fraction)
    }

    private func caption(for phase: Pomodoro.Phase) -> String {
        let pomodoro = model.pomodoro
        switch phase {
        case .idle:
            return "\(model.store.config.focusMinutes) min focus"
        case .focus:
            guard let start = pomodoro.startDate else { return "" }
            let score = model.store.summary(in: DateInterval(start: start, end: max(start, pomodoro.now))).score
            if let score { return "focus score \(Int(score.rounded()))" }
            return "ends \(pomodoro.endDate?.formatted(date: .omitted, time: .shortened) ?? "")"
        case .rest:
            return "break"
        }
    }
}
