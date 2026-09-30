import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var diagnostics: RavenDiagnostics
    @EnvironmentObject private var vision: VisionEngine
    @EnvironmentObject private var ble: RavenBLEManager

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                RavenTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        sessionCard
                        LazyVGrid(columns: columns, spacing: 12) {
                            MetricCard(title: "UI FPS", value: String(format: "%.0f", diagnostics.uiFPS), icon: "speedometer")
                            MetricCard(title: "MODEL FPS", value: String(format: "%.1f", vision.modelFPS), icon: "brain.head.profile")
                            MetricCard(title: "INFERENCE", value: String(format: "%.1f ms", vision.inferenceMs), icon: "bolt.fill")
                            MetricCard(title: "ESP32", value: ble.state.rawValue, icon: "cpu")
                        }

                        Button {
                            appState.selectedTab = .capture
                        } label: {
                            HStack {
                                Image(systemName: "record.circle")
                                Text("OPEN CAPTURE")
                                    .fontWeight(.bold)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(16)
                            .foregroundStyle(.white)
                            .background(RavenTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
            .navigationTitle("RAVEN")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("RAVEN ENGINE AI")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Text("NATIVE iOS CONTROL CORE • BUILD 0.1.1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RavenTheme.textSecondary)
            }
            Spacer()
            Circle()
                .fill(appState.sessionActive ? RavenTheme.accent : Color.white.opacity(0.16))
                .frame(width: 12, height: 12)
                .shadow(color: RavenTheme.accent.opacity(appState.sessionActive ? 0.8 : 0), radius: 8)
        }
    }

    private var sessionCard: some View {
        RavenCard {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(appState.sessionActive ? "SESSION ACTIVE" : "SESSION STANDBY")
                        .font(.headline)
                    Text(appState.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(RavenTheme.textSecondary)
                }
                Spacer()
                Button(appState.sessionActive ? "STOP" : "START") {
                    appState.toggleSession()
                }
                .buttonStyle(.borderedProminent)
                .tint(RavenTheme.accent)
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        RavenCard {
            Image(systemName: icon)
                .foregroundStyle(RavenTheme.accent)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(RavenTheme.textSecondary)
        }
    }
}
