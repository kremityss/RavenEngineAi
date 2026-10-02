import Foundation
import CoreML
import CoreVideo
import ImageIO
import Vision

struct RavenInferenceStats {
    let modelLoaded: Bool
    let completedFrames: UInt64
    let droppedFrames: UInt64
    let detections: Int
    let inferenceMs: Double
    let modelFPS: Double
    let target: RavenAimTarget?
}

final class RavenInferenceEngine {
    private let queue = DispatchQueue(label: "Raven.Inference", qos: .userInteractive)
    private let stateLock = NSLock()
    private let targeting = RavenTargetingEngine()

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
                completion(self.snapshot(detections: 0, inferenceMs: 0, target: nil))
                return
            }

            let started = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                completion(self.snapshot(detections: 0, inferenceMs: 0, target: nil))
                return
            }

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            let target = self.targeting.select(from: observations)

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

            completion(self.snapshot(
                detections: observations.count,
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
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            return request
        } catch {
            return nil
        }
    }

    private func snapshot(
        detections: Int,
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
            target: target
        )
    }

    private func markIdle() {
        stateLock.lock()
        busy = false
        stateLock.unlock()
    }
}
