import Foundation
import CoreML
import Vision

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
    @Published var modelName = "Checking model..."
    @Published var modelFPS: Double = 0
    @Published var inferenceMs: Double = 0
    @Published var status = "Validating Core ML model"

    private var model: MLModel?

    init() {
        loadModel()
    }

    func setEnabled(_ value: Bool) {
        enabled = value

        guard model != nil else {
            enabled = false
            status = "RavenDetector is not available in the app bundle"
            return
        }

        status = value ? "Model ready • waiting for ReplayKit frames" : "Engine paused"
    }

    private func loadModel() {
        guard let url = Bundle.main.url(forResource: "RavenDetector", withExtension: "mlmodelc") else {
            modelName = "RavenDetector missing"
            status = "Compiled model not found in app bundle"
            return
        }

        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            model = loaded

            let description = loaded.modelDescription
            let input = description.inputDescriptionsByName.keys.sorted().joined(separator: ", ")
            let output = description.outputDescriptionsByName.keys.sorted().joined(separator: ", ")

            modelName = "RavenDetector"
            status = "Loaded • input: \(input) • output: \(output)"
        } catch {
            model = nil
            modelName = "RavenDetector load failed"
            status = error.localizedDescription
        }
    }
}
