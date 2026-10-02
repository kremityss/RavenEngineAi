import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("raven.haptics") private var haptics = true
    @AppStorage("raven.autoReconnect") private var autoReconnect = true

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RavenTheme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("Performance") {
                        Toggle("Performance Mode", isOn: $appState.performanceMode)
                        Toggle("Auto-reconnect RavenLink", isOn: $autoReconnect)
                    }
                    Section("Interface") {
                        Toggle("Haptics", isOn: $haptics)
                    }
                    Section("Build") {
                        LabeledContent("Channel", value: "Native iOS")
                        LabeledContent("Version", value: versionLabel)
                        LabeledContent("Protocol", value: "RavenLink v1")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }
}
