import SwiftUI

enum RavenTheme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let panel = Color(red: 0.075, green: 0.075, blue: 0.095)
    static let accent = Color(red: 0.92, green: 0.08, blue: 0.12)
    static let textSecondary = Color.white.opacity(0.62)

    static let backgroundGradient = LinearGradient(
        colors: [background, Color(red: 0.08, green: 0.025, blue: 0.035)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct RavenCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RavenTheme.panel.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}
