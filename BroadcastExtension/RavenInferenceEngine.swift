import Foundation
import CoreML
import CoreVideo
import Vision

struct RavenInferenceStats {
    let modelLoaded: Bool
    let completedFrames: UInt64
    let droppedFrames: UInt64
    let detections: Int
    let inferenceMs: Double
    let modelFPS: Double
}

final class RavenInferenceEngine {
    private let queue = DispatchQueue(label: "Raven.Inference", qos: .userInteractive)
    private let stateLock = NSLock()

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

    func submit(
        pixelBuffer: CVPixelBuffer,
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
                completion(self.snapshot(detections: 0, inferenceMs: 0))
                return
            }

            let started = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                completion(self.snapshot(detections: 0, inferenceMs: 0))
                return
            }

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            let detections = (request.results as? [VNRecognizedObjectObservation])?.count ?? 0

            self.stateLock.lock()
            self.completedFrames &+= 1
            self.fpsWindowFrames &+= 1
            let now = CFAbsoluteTimeGetCurrent()
            let window = now - self.fpsWindowStart
            if window >= 1 {
                self.measuredFPS = Double(self.fpsWindowFrames) / window
                self.fpsWindowFrames = 0
                self.fpsWindowStart = now
            }
            self.stateLock.unlock()

            completion(self.snapshot(detections: detections, inferenceMs: elapsedMs))
        }
    }

    private func makeRequest() -> VNCoreMLRequest? {
        guard let url = Bundle.main.url(forResource: "RavenDetector", withExtension: "mlmodelc") else {
            return nil
        }

        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            return request
        } catch {
            return nil
        }
    }

    private func snapshot(detections: Int, inferenceMs: Double) -> RavenInferenceStats {
        stateLock.lock()
        defer { stateLock.unlock() }
        return RavenInferenceStats(
            modelLoaded: request != nil,
            completedFrames: completedFrames,
            droppedFrames: droppedFrames,
            detections: detections,
            inferenceMs: inferenceMs,
            modelFPS: measuredFPS
        )
    }

    private func markIdle() {
        stateLock.lock()
        busy = false
        stateLock.unlock()
    }
}
