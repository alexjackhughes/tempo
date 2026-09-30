import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = model.store
        let idleMinutes = Binding(
            get: { Int(store.config.idleThreshold / 60) },
            set: { store.config.idleThreshold = TimeInterval($0 * 60) })

        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Settings", subtitle: "Everything is stored locally on this Mac") { EmptyView() }

            SettingCard(title: "Focus length",
                        description: "How long each focus session runs before a break.",
                        hint: "Classic pomodoros are 25 minutes; 20 works well for shorter tasks.") {
                NumberStepper(value: $store.config.focusMinutes, range: 5...90, step: 5, unit: " min")
            }

            SettingCard(title: "Break length", description: "The break that starts automatically after a completed session.") {
                NumberStepper(value: $store.config.breakMinutes, range: 1...30, unit: " min")
            }

            SettingCard(title: "Daily goal", description: "Focus sessions you're aiming to complete each day.") {
                NumberStepper(value: $store.config.dailyPomodoroGoal, range: 1...24)
            }

            SettingCard(title: "Idle detection",
                        description: "Stop counting time after this long without keyboard or mouse input.",
                        hint: "Raise this if you often watch or read without touching the keyboard.") {
                NumberStepper(value: idleMinutes, range: 1...30, unit: " min")
            }

            SettingCard(title: "Website tracking",
                        description: "Record the domain of the active tab in Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera.",
                        hint: "Only the domain is stored, never the full URL. Firefox doesn't support this.") {
                Toggle("", isOn: $store.config.trackBrowserURLs).toggleStyle(.switch).tint(T.fg).labelsHidden()
            } extra: {
                if !model.tracker.browser.deniedBrowsers.isEmpty {
                    HStack(spacing: 10) {
                        StatusDot(color: T.amber, size: 6)
                        Text("Access was denied for some browsers.").font(.geist(13)).foregroundStyle(T.fg)
                        Spacer()
                        Button("Open Automation settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                        }
                        .buttonStyle(.secondary)
                    }
                    .padding(12)
                    .background(T.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.amber.opacity(0.3)))
                }
            }

            SettingCard(title: "Pause tracking", description: "Temporarily stop recording activity.") {
                Toggle("", isOn: $store.trackingPaused).toggleStyle(.switch).tint(T.fg).labelsHidden()
            }

            SettingCard(title: "Launch at login", description: "Start Tempo automatically when you log in.",
                        hint: loginError) {
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).tint(T.fg).labelsHidden()
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            SettingCard(title: "Data", description: "Plain JSON files: one per day of activity, plus your sessions and rules.",
                        hint: "Nothing ever leaves your Mac.") {
                Button("Show in Finder") { NSWorkspace.shared.open(store.directory) }.buttonStyle(.secondary)
            } extra: {
                Text(store.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.mono(12)).foregroundStyle(T.fg2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.subtle, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.border))
            }
        }
        .onChange(of: store.config) { store.saveConfigIfNeeded() }
    }
}

private struct SettingCard<Control: View, Extra: View>: View {
    let title: String
    let description: String
    var hint: String?
    @ViewBuilder var control: Control
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.geist(18, .semibold)).tracking(-0.4).foregroundStyle(T.fg)
                        Text(description).font(.geist(14)).foregroundStyle(T.fg2)
                    }
                    Spacer()
                    control
                }
                extra
            }
            .padding(24)
            if let hint {
                Text(hint)
                    .font(.geist(13)).foregroundStyle(T.fg2)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.subtle)
                    .overlay(alignment: .top) { Hairline() }
            }
        }
        .background(T.surface)
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.border))
    }
}

extension SettingCard where Extra == EmptyView {
    init(title: String, description: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.init(title: title, description: description, hint: hint, control: control, extra: { EmptyView() })
    }
}
