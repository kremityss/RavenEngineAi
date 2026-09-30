import SwiftUI

struct CaptureView: View {
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ZStack {
                RavenTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        startCaptureCard
                        statusCard
                        helpCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Capture")
        }
    }

    private var header: some View {
        RavenCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("RAVEN CAPTURE", systemImage: "record.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Dedicated screen-capture control for the Raven broadcast extension.")
                    .font(.subheadline)
                    .foregroundStyle(RavenTheme.textSecondary)
            }
        }
    }

    private var startCaptureCard: some View {
        RavenCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("SCREEN BROADCAST")
                    .font(.caption.bold())
                    .foregroundStyle(RavenTheme.textSecondary)

                Text("Start Raven Capture")
                    .font(.title3.bold())

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(RavenTheme.accent)
                        .frame(height: 64)

                    HStack(spacing: 10) {
                        Image(systemName: "record.circle")
                            .font(.title2)
                        Text("START SCREEN CAPTURE")
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)

                    BroadcastPickerView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                }

                Text("iOS should open the system broadcast sheet. Select Raven Capture, then start the broadcast.")
                    .font(.caption)
                    .foregroundStyle(RavenTheme.textSecondary)
            }
        }
    }

    private var statusCard: some View {
        RavenCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Extension", systemImage: "puzzlepiece.extension")
                    .font(.headline)
                LabeledContent("Bundle", value: "RavenBroadcast.appex")
                LabeledContent("Target", value: "Raven Capture")
                LabeledContent("Mode", value: "ReplayKit")
            }
        }
    }

    private var helpCard: some View {
        RavenCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showHelp.toggle()
                } label: {
                    HStack {
                        Label("Capture troubleshooting", systemImage: "wrench.and.screwdriver")
                        Spacer()
                        Image(systemName: showHelp ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)

                if showHelp {
                    Text("If the broadcast sheet opens but Raven Capture is missing, the extension was not registered correctly during signing. If the red control does nothing, we will inspect ReplayKit behavior on the installed build.")
                        .font(.caption)
                        .foregroundStyle(RavenTheme.textSecondary)
                }
            }
        }
    }
}
