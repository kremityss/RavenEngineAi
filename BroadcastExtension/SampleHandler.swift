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

    private var captureFrames: UInt64 = 0
    private var lastLogFrame: UInt64 = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        captureFrames = 0
        lastLogFrame = 0
        bleOutput.start()
        logger.info("Raven capture started; modelLoaded=\(self.inference.isModelLoaded)")
    }

    override func broadcastPaused() {
        logger.info("Raven capture paused")
    }

    override func broadcastResumed() {
        logger.info("Raven capture resumed")
    }

    override func broadcastFinished() {
        bleOutput.stop()
        logger.info("Raven capture finished after \(self.captureFrames) video frames")
    }
    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        captureFrames &+= 1
        let orientation = videoOrientation(from: sampleBuffer)

        inference.submit(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        ) { [weak self] stats in
            guard let self else { return }

            if let target = stats.target {
                self.bleOutput.send(target: target)
            }

            guard stats.completedFrames >= self.lastLogFrame + 60 else { return }
            self.lastLogFrame = stats.completedFrames
            let targetState = stats.target == nil ? "none" : "locked"
            self.logger.info(
                "AI fps=\(stats.modelFPS, format: .fixed(precision: 1)) latency=\(stats.inferenceMs, format: .fixed(precision: 1))ms detections=\(stats.detections) target=\(targetState, privacy: .public) ble=\(self.bleOutput.state.rawValue, privacy: .public) drops=\(stats.droppedFrames)"
            )
        }
    }

    private func videoOrientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        var mode: CMAttachmentMode = .shouldNotPropagate
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
