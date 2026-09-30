import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var diagnostics: RavenDiagnostics

    var body: some View {
        NavigationStack {
            ZStack {
                RavenTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        RavenCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("iPhone Runtime", systemImage: "iphone.gen3")
                                    .font(.headline)
                                LabeledContent("Device", value: diagnostics.deviceName)
                                LabeledContent("iOS", value: diagnostics.systemVersion)
                                LabeledContent("Memory", value: String(format: "%.1f GB", diagnostics.physicalMemoryGB))
                                LabeledContent("UI FPS", value: String(format: "%.1f", diagnostics.uiFPS))
                                LabeledContent("Thermal", value: diagnostics.thermalState)
                            }
                        }

                        RavenCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PERFORMANCE POLICY").font(.caption.bold())
                                Text("Measured counters stay honest: model and capture metrics remain zero until real frames are attached to the inference pipeline.")
                                    .font(.subheadline)
                                    .foregroundStyle(RavenTheme.textSecondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Device")
        }
    }
}
