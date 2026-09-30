import Foundation

@MainActor
final class VisionEngine: ObservableObject {
    enum InputSize: Int, CaseIterable, Identifiable {
        case compact = 320
        case balanced = 416
        case quality = 640
        var id: Int { rawValue }
    }

    @Published var enabled = false
    @Published var trackingEnabled = true
    @Published var confidence: Double = 0.55
    @Published var fovRadius: Double = 145
    @Published var inputSize: InputSize = .balanced
    @Published var modelName = "No model loaded"
    @Published var modelFPS: Double = 0
    @Published var inferenceMs: Double = 0
    @Published var status = "Engine ready"

    func setEnabled(_ value: Bool) {
        enabled = value
        status = value ? "Waiting for capture frames" : "Engine paused"
    }
}
