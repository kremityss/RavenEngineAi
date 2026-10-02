import ReplayKit
import CoreMedia
import CoreVideo
import ImageIO
import os

final class SampleHandler: RPBroadcastSampleHandler {
    private let logger = Logger(
        subsystem: "com.kremcheats.RavenEngineAI.broadcast",
        category: "Capture"
    )

    private let inference = RavenInferenceEngine()
    private let bleOutput = RavenBLEOutput()
    private let liveServer = RavenLiveServer()
    private let preview = RavenPreviewEncoder()

    private let stateLock = NSLock()
    private var aimEnabled = true
    private var captureFrames: UInt64 = 0
    private var captureWindowFrames: UInt64 = 0
    private var captureWindowStart = CFAbsoluteTimeGetCurrent()
    private var captureFPS: Double = 0
    private var streamFPS: Double = 0
    private var previewWidth = 0
    private var previewHeight = 0
    private var lastLogFrame: UInt64 = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        captureFrames = 0
        captureWindowFrames = 0
        captureWindowStart = CFAbsoluteTimeGetCurrent()
        captureFPS = 0
        streamFPS = 0
        previewWidth = 0
        previewHeight = 0
        lastLogFrame = 0

        liveServer.onConfig = { [weak self] payload in
            guard let self else { return }
            self.inference.updateSettings(payload)
            self.bleOutput.updateSettings(payload)
            if let enabled = payload["aim_enabled"] as? Bool {
                self.stateLock.lock()
                self.aimEnabled = enabled
                self.stateLock.unlock()
            }
        }

        liveServer.start(port: 8788)
        bleOutput.start()
        publishInitialState()

        logger.info(
            "Raven iPhone runtime started; modelLoaded=\(self.inference.isModelLoaded)"
        )
    }

    override func broadcastPaused() {
        logger.info("Raven capture paused")
    }

    override func broadcastResumed() {
        logger.info("Raven capture resumed")
    }

    override func broadcastFinished() {
        liveServer.stop()
        bleOutput.stop()
        logger.info("Raven capture finished after \(self.captureFrames) video frames")
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        updateCaptureFPS()
        let orientation = videoOrientation(from: sampleBuffer)

        if liveServer.wantsFrames {
            preview.submit(pixelBuffer: pixelBuffer, orientation: orientation) { [weak self] data, stats in
                guard let self else { return }
                self.stateLock.lock()
                self.streamFPS = stats.fps
                self.previewWidth = stats.width
                self.previewHeight = stats.height
                self.stateLock.unlock()
                self.liveServer.updateFrame(data)
            }
        }

        inference.submit(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        ) { [weak self] stats in
            guard let self else { return }

            self.stateLock.lock()
            let canAim = self.aimEnabled
            let captureFPS = self.captureFPS
            let streamFPS = self.streamFPS
            let previewWidth = self.previewWidth
            let previewHeight = self.previewHeight
            self.stateLock.unlock()

            if canAim, let target = stats.target {
                self.bleOutput.send(target: target)
            }

            // Protect the 30 FPS neural floor first. Raise dashboard preview
            // toward 45/60 FPS only when CoreML has enough measured headroom.
            let previewTarget: Double
            if stats.modelFPS >= 52.0 && stats.inferenceMs <= 20.0 {
                previewTarget = 60.0
            } else if stats.modelFPS >= 40.0 && stats.inferenceMs <= 25.0 {
                previewTarget = 45.0
            } else {
                previewTarget = 30.0
            }
            self.preview.setTargetFPS(previewTarget)

            let detections: [[String: Any]] = stats.detections.prefix(24).map {
                let b = $0.boundingBox
                return [
                    "label": $0.label,
                    "confidence": $0.confidence,
                    "x": b.origin.x,
                    "y": b.origin.y,
                    "w": b.size.width,
                    "h": b.size.height
                ]
            }

            var targetJSON: [String: Any]? = nil
            if let target = stats.target {
                let b = target.boundingBox
                targetJSON = [
                    "confidence": target.confidence,
                    "dx": target.dx,
                    "dy": target.dy,
                    "x": b.origin.x,
                    "y": b.origin.y,
                    "w": b.size.width,
                    "h": b.size.height
                ]
            }

            let streamPass = !self.liveServer.wantsFrames || streamFPS >= 29.5
            let performanceOK = stats.modelFPS >= RavenInferenceEngine.targetFPS && streamPass

            var metrics: [String: Any] = [
                "capture_fps": captureFPS,
                "stream_fps": streamFPS,
                "model_fps": stats.modelFPS,
                "infer_ms": stats.inferenceMs,
                "detections": stats.detections.count,
                "dropped_frames": stats.droppedFrames,
                "completed_frames": stats.completedFrames,
                "model_loaded": stats.modelLoaded,
                "hid": self.bleOutput.state == .connected,
                "esp_mode": "abs",
                "frame": [previewWidth, previewHeight],
                "performance_target_fps": RavenInferenceEngine.targetFPS,
                "stretch_target_fps": RavenInferenceEngine.stretchTargetFPS,
                "stream_target_fps": previewTarget,
                "performance_ok": performanceOK
            ]
            if let targetJSON { metrics["target"] = targetJSON }

            self.liveServer.updateState([
                "inference_location": "iphone",
                "ready": stats.modelLoaded,
                "model_name": "YOLO26n CoreML",
                "device": "iPhone",
                "aim_enabled": canAim,
                "ble_state": self.bleOutput.state.rawValue,
                "metrics": metrics,
                "detections": detections,
                "error": NSNull()
            ])

            guard stats.completedFrames >= self.lastLogFrame + 60 else { return }
            self.lastLogFrame = stats.completedFrames
            let targetState = stats.target == nil ? "none" : "locked"
            self.logger.info(
                "AI fps=\(stats.modelFPS, format: .fixed(precision: 1)) latency=\(stats.inferenceMs, format: .fixed(precision: 1))ms stream=\(streamFPS, format: .fixed(precision: 1)) capture=\(captureFPS, format: .fixed(precision: 1)) detections=\(stats.detections.count) target=\(targetState, privacy: .public) ble=\(self.bleOutput.state.rawValue, privacy: .public) drops=\(stats.droppedFrames)"
            )
        }
    }

    private func publishInitialState() {
        liveServer.updateState([
            "inference_location": "iphone",
            "ready": inference.isModelLoaded,
            "model_name": "YOLO26n CoreML",
            "device": "iPhone",
            "aim_enabled": aimEnabled,
            "ble_state": bleOutput.state.rawValue,
            "metrics": [
                "capture_fps": 0,
                "stream_fps": 0,
                "model_fps": 0,
                "infer_ms": 0,
                "detections": 0,
                "dropped_frames": 0,
                "completed_frames": 0,
                "model_loaded": inference.isModelLoaded,
                "hid": false,
                "esp_mode": "abs",
                "frame": [0, 0],
                "performance_target_fps": RavenInferenceEngine.targetFPS,
                "performance_ok": false
            ],
            "detections": [],
            "error": NSNull()
        ])
    }

    private func updateCaptureFPS() {
        stateLock.lock()
        captureFrames &+= 1
        captureWindowFrames &+= 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - captureWindowStart
        if elapsed >= 1.0 {
            captureFPS = Double(captureWindowFrames) / elapsed
            captureWindowFrames = 0
            captureWindowStart = now
        }
        stateLock.unlock()
    }

    private func videoOrientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        var mode: CMAttachmentMode = kCMAttachmentMode_ShouldNotPropagate
        guard let value = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: &mode
        ) as? NSNumber,
        let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) else {
            return .up
        }
        return orientation
    }
}