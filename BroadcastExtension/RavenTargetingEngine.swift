import Foundation
import Vision

struct RavenAimTarget {
    let dx: Double
    let dy: Double
    let confidence: Double
    let boundingBox: CGRect
}

struct RavenTargetingConfig {
    var confidenceThreshold: Double = 0.45
    var fovRadius: Double = 0.30
    var headRatio: Double = 0.20
    var smoothing: Double = 0.58
    var maxNormalizedStep: Double = 0.18
}

final class RavenTargetingEngine {
    private var config = RavenTargetingConfig()
    private var smoothedDX: Double = 0
    private var smoothedDY: Double = 0
    private var hasHistory = false

    func reset() {
        smoothedDX = 0
        smoothedDY = 0
        hasHistory = false
    }
    func select(from observations: [VNRecognizedObjectObservation]) -> RavenAimTarget? {
        let candidates = observations.compactMap { observation -> (VNRecognizedObjectObservation, Double)? in
            guard let label = observation.labels.first,
                  label.identifier.lowercased() == "enemy",
                  Double(label.confidence) >= config.confidenceThreshold else {
                return nil
            }

            let box = observation.boundingBox
            let x = box.midX
            let aimY = box.maxY - box.height * config.headRatio
            let dx = x - 0.5
            let dy = 0.5 - aimY
            let distance = hypot(dx, dy)

            guard distance <= config.fovRadius else { return nil }
            let score = distance / max(Double(label.confidence), 0.001)
            return (observation, score)
        }

        guard let chosen = candidates.min(by: { $0.1 < $1.1 })?.0,
              let label = chosen.labels.first else {
            reset()
            return nil
        }

        let box = chosen.boundingBox
        let rawDX = box.midX - 0.5
        let rawDY = 0.5 - (box.maxY - box.height * config.headRatio)
        let limitedDX = max(-config.maxNormalizedStep, min(config.maxNormalizedStep, rawDX))
        let limitedDY = max(-config.maxNormalizedStep, min(config.maxNormalizedStep, rawDY))
        if hasHistory {
            smoothedDX = smoothedDX * config.smoothing + limitedDX * (1 - config.smoothing)
            smoothedDY = smoothedDY * config.smoothing + limitedDY * (1 - config.smoothing)
        } else {
            smoothedDX = limitedDX
            smoothedDY = limitedDY
            hasHistory = true
        }

        return RavenAimTarget(
            dx: smoothedDX,
            dy: smoothedDY,
            confidence: Double(label.confidence),
            boundingBox: box
        )
    }
}
