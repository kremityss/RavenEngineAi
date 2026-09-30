import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable { case dashboard, vision, esp32, device, settings }

    @Published var selectedTab: Tab = .dashboard
    @Published var performanceMode = true
    @Published var sessionActive = false
    @Published var statusMessage = "Ready"

    func toggleSession() {
        sessionActive.toggle()
        statusMessage = sessionActive ? "Raven session active" : "Raven session stopped"
    }
}
