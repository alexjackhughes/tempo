import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = model.store
        Form {
            Section("Pomodoro") {
                Stepper("Focus length: \(store.config.focusMinutes) min",
                        value: $store.config.focusMinutes, in: 5...90, step: 5)
                Stepper("Break length: \(store.config.breakMinutes) min",
                        value: $store.config.breakMinutes, in: 1...30)
                Stepper("Daily goal: \(store.config.dailyPomodoroGoal) pomodoros",
                        value: $store.config.dailyPomodoroGoal, in: 1...24)
            }

            Section("Tracking") {
                Toggle("Pause tracking", isOn: $store.trackingPaused)
                Stepper("Stop counting after \(Int(store.config.idleThreshold / 60)) min of no keyboard/mouse input",
                        value: $store.config.idleThreshold, in: 60...1800, step: 60)
                Toggle("Record website domains in browsers", isOn: $store.config.trackBrowserURLs)
                Text("Supports Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera. macOS asks once per browser for permission to read the current tab. Only the domain is stored, never the full URL. Firefox has no scripting support so it shows as the app only.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.tracker.browser.deniedBrowsers.isEmpty {
                    HStack {
                        Label("Browser access was denied for some browsers.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Open Automation settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Data folder") {
                    Button("Show in Finder") { NSWorkspace.shared.open(store.directory) }
                }
                Text("Everything is stored locally as JSON in \(store.directory.path). Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.config) { store.saveConfigIfNeeded() }
    }
}
