import Foundation
import Vision

struct RavenAimTarget {
    let dx: Double
    let dy: Double
    let confidence: Double
    let boundingBox: CGRect
}

struct RavenTargetingConfig {
    var confidenceThreshold: Double = 0.18
    var fovRadius: Double = 0.41
    var headRatio: Double = 0.18
    var smoothing: Double = 0.35
    var maxNormalizedStep: Double = 0.18
}

final class RavenTargetingEngine {
    private var config = RavenTargetingConfig()
    private var smoothedDX: Double = 0
    private var smoothedDY: Double = 0
    private var hasHistory = false

    func update(from payload: [String: Any]) {
        if let v = payload["confidence"] as? NSNumber {
            config.confidenceThreshold = max(0.05, min(0.90, v.doubleValue))
        }
        if let v = payload["fov_ratio"] as? NSNumber {
            config.fovRadius = max(0.10, min(0.70, v.doubleValue * 0.5))
        }
        if let v = payload["smoothing"] as? NSNumber {
            config.smoothing = max(0.0, min(0.95, v.doubleValue))
        }
        if let v = payload["max_normalized_step"] as? NSNumber {
            config.maxNormalizedStep = max(0.02, min(0.45, v.doubleValue))
        }
        if let v = payload["bone"] as? NSNumber {
            switch v.intValue {
            case 1: config.headRatio = 0.30
            case 2: config.headRatio = 0.43
            case 3: config.headRatio = 0.68
            default: config.headRatio = 0.18
            }
        }
    }

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