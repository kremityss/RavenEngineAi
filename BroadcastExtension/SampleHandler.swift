import ReplayKit
import CoreMedia
import CoreVideo
import os

final class SampleHandler: RPBroadcastSampleHandler {
    private let logger = Logger(
        subsystem: "com.kremcheats.RavenEngineAI.broadcast",
        category: "Capture"
    )
    private var frameCount: UInt64 = 0
    private var firstPTS: CMTime?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        frameCount = 0
        firstPTS = nil
        logger.info("Raven capture started")
    }

    override func broadcastPaused() {
        logger.info("Raven capture paused")
    }

    override func broadcastResumed() {
        logger.info("Raven capture resumed")
    }

    override func broadcastFinished() {
        logger.info("Raven capture finished after \(self.frameCount) video frames")
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstPTS == nil { firstPTS = pts }
        frameCount &+= 1

        // Core ML / Vision processing attaches here next.
        // Keep this callback non-blocking with a bounded worker pipeline.
    }
}
