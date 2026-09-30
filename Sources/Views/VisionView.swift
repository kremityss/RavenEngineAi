import SwiftUI

struct VisionView: View {
    @EnvironmentObject private var vision: VisionEngine

    var body: some View {
        NavigationStack {
            ZStack {
                RavenTheme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("FOV") {
                        FOVPreview(radius: vision.fovRadius)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    Section("Engine") {
                        Toggle("Vision Engine", isOn: Binding(
                            get: { vision.enabled },
                            set: { vision.setEnabled($0) }
                        ))
                        Toggle("Target Tracking", isOn: $vision.trackingEnabled)
                        LabeledContent("Status", value: vision.status)
                        LabeledContent("Model", value: vision.modelName)
                    }

                    Section("Detection") {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Confidence")
                                Spacer()
                                Text(String(format: "%.0f%%", vision.confidence * 100))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $vision.confidence, in: 0.1...0.95)
                        }

                        Picker("Input", selection: $vision.inputSize) {
                            ForEach(VisionEngine.InputSize.allCases) { size in
                                Text("\(size.rawValue) × \(size.rawValue)").tag(size)
                            }
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("FOV Radius")
                                Spacer()
                                Text("\(Int(vision.fovRadius)) px").foregroundStyle(.secondary)
                            }
                            Slider(value: $vision.fovRadius, in: 50...350)
                        }
                    }

                    Section("Performance") {
                        LabeledContent("Model FPS", value: String(format: "%.1f", vision.modelFPS))
                        LabeledContent("Inference", value: String(format: "%.1f ms", vision.inferenceMs))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Vision")
        }
    }
}
