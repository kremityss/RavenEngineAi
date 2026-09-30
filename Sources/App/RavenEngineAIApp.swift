import SwiftUI

@main
struct RavenEngineAIApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var diagnostics = RavenDiagnostics()
    @StateObject private var vision = VisionEngine()
    @StateObject private var ble = RavenBLEManager()
    @StateObject private var wifi = RavenWiFiClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(diagnostics)
                .environmentObject(vision)
                .environmentObject(ble)
                .environmentObject(wifi)
                .preferredColorScheme(.dark)
        }
    }
}
