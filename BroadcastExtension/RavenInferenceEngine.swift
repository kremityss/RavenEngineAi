import Foundation
import CoreML
import CoreVideo
import ImageIO
import Vision

struct RavenDetection {
    let label: String
    let confidence: Double
    let boundingBox: CGRect
}

struct RavenInferenceStats {
    let modelLoaded: Bool
    let completedFrames: UInt64
    let droppedFrames: UInt64
    let detections: [RavenDetection]
    let inferenceMs: Double
    let modelFPS: Double
    let target: RavenAimTarget?
    let performanceOK: Bool
}

final class RavenInferenceEngine {
    static let targetFPS: Double = 30
    static let stretchTargetFPS: Double = 60

    private let queue = DispatchQueue(
        label: "Raven.Inference",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    private let stateLock = NSLock()
    private let targeting = RavenTargetingEngine()
    private let sequenceHandler = VNSequenceRequestHandler()

    private var request: VNCoreMLRequest?
    private var busy = false
    private var completedFrames: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var fpsWindowFrames: UInt64 = 0
    private var fpsWindowStart = CFAbsoluteTimeGetCurrent()
    private var measuredFPS: Double = 0

    init() {
        request = makeRequest()
    }

    var isModelLoaded: Bool {
        request != nil
    }

    func updateSettings(_ payload: [String: Any]) {
        queue.async { [weak self] in
            self?.targeting.update(from: payload)
        }
    }

    func submit(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (RavenInferenceStats) -> Void
    ) {
        stateLock.lock()
        if busy {
            droppedFrames &+= 1
            stateLock.unlock()
            return
        }
        busy = true
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer { self.markIdle() }

            guard let request = self.request else {
                completion(self.snapshot(detections: [], inferenceMs: 0, target: nil))
                return
            }

            let started = CFAbsoluteTimeGetCurrent()

            do {
                // Reusing VNSequenceRequestHandler avoids rebuilding a Vision
                // handler for every ReplayKit frame.
                try autoreleasepool {
                    try self.sequenceHandler.perform(
                        [request],
                        on: pixelBuffer,
                        orientation: orientation
                    )
                }
            } catch {
                completion(self.snapshot(detections: [], inferenceMs: 0, target: nil))
                return
            }

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            let detections = observations.compactMap { observation -> RavenDetection? in
                guard let label = observation.labels.first else { return nil }
                return RavenDetection(
                    label: label.identifier,
                    confidence: Double(label.confidence),
                    boundingBox: observation.boundingBox
                )
            }
            let target = self.targeting.select(from: observations)

            self.stateLock.lock()
            self.completedFrames &+= 1
            self.fpsWindowFrames &+= 1
            let now = CFAbsoluteTimeGetCurrent()
            let window = now - self.fpsWindowStart
            if window >= 1.0 {
                self.measuredFPS = Double(self.fpsWindowFrames) / window
                self.fpsWindowFrames = 0
                self.fpsWindowStart = now
            }
            self.stateLock.unlock()

            completion(self.snapshot(
                detections: detections,
                inferenceMs: elapsedMs,
                target: target
            ))
        }
    }

    private func makeRequest() -> VNCoreMLRequest? {
        let bundles = [Bundle.main, Bundle(for: RavenInferenceEngine.self)]
        let modelURL = bundles.compactMap {
            $0.url(forResource: "RavenDetector", withExtension: "mlmodelc")
        }.first

        guard let modelURL else { return nil }

        do {
            let configuration = MLModelConfiguration()
            // Keep the game GPU free. Heavy inference stays eligible for ANE,
            // with CPU used only for unsupported glue ops.
            configuration.computeUnits = .cpuAndNeuralEngine
            configuration.preferBackgroundProcessing = false

            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            request.preferBackgroundProcessing = false
            return request
        } catch {
            print("RavenDetector load failed: \(error)")
            return nil
        }
    }

    private func snapshot(
        detections: [RavenDetection],
        inferenceMs: Double,
        target: RavenAimTarget?
    ) -> RavenInferenceStats {
        stateLock.lock()
        defer { stateLock.unlock() }
        return RavenInferenceStats(
            modelLoaded: request != nil,
            completedFrames: completedFrames,
            droppedFrames: droppedFrames,
            detections: detections,
            inferenceMs: inferenceMs,
            modelFPS: measuredFPS,
            target: target,
            performanceOK: measuredFPS >= Self.targetFPS
        )
    }

    private func markIdle() {
        stateLock.lock()
        busy = false
        stateLock.unlock()
    }
}