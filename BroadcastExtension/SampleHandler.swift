import ReplayKit
import CoreMedia
import CoreVideo
import os

final class SampleHandler: RPBroadcastSampleHandler {
    private let logger = Logger(
        subsystem: "com.kremcheats.RavenEngineAI.broadcast",
        category: "Capture"
    )
    private let inference = RavenInferenceEngine()

    private var captureFrames: UInt64 = 0
    private var lastLogFrame: UInt64 = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        captureFrames = 0
        lastLogFrame = 0
        logger.info("Raven capture started; modelLoaded=\(self.inference.isModelLoaded)")
    }

    override func broadcastPaused() {
        logger.info("Raven capture paused")
    }

    override func broadcastResumed() {
        logger.info("Raven capture resumed")
    }

    override func broadcastFinished() {
        logger.info("Raven capture finished after \(self.captureFrames) video frames")
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        captureFrames &+= 1

        inference.submit(pixelBuffer: pixelBuffer) { [weak self] stats in
            guard let self else { return }
            guard stats.completedFrames >= self.lastLogFrame + 60 else { return }
            self.lastLogFrame = stats.completedFrames
            self.logger.info(
                "AI fps=\(stats.modelFPS, format: .fixed(precision: 1)) latency=\(stats.inferenceMs, format: .fixed(precision: 1))ms detections=\(stats.detections) drops=\(stats.droppedFrames)"
            )
        }
    }
}
