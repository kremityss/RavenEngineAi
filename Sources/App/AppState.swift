import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case dashboard
        case capture
        case vision
        case esp32
        case device
        case settings
    }

    @Published var selectedTab: Tab = .dashboard
    @Published var performanceMode = true
    @Published var sessionActive = false
    @Published var statusMessage = "Ready"

    func toggleSession() {
        sessionActive.toggle()
        statusMessage = sessionActive ? "Raven session active" : "Raven session stopped"
    }
}
