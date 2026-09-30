import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(AppState.Tab.dashboard)

            VisionView()
                .tabItem { Label("Vision", systemImage: "viewfinder") }
                .tag(AppState.Tab.vision)

            ESP32View()
                .tabItem { Label("ESP32", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppState.Tab.esp32)

            DeviceView()
                .tabItem { Label("Device", systemImage: "iphone.gen3") }
                .tag(AppState.Tab.device)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(AppState.Tab.settings)
        }
        .tint(RavenTheme.accent)
    }
}
