import Foundation
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

final class RavenPreviewEncoder {
    struct Stats {
        let fps: Double
        let width: Int
        let height: Int
    }

    private let queue = DispatchQueue(label: "Raven.Preview", qos: .userInitiated)
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var busy = false
    private var lastSubmit = CFAbsoluteTimeGetCurrent()
    private var windowStart = CFAbsoluteTimeGetCurrent()
    private var windowFrames = 0
    private var measuredFPS: Double = 0

    private var requestedFPS: Double = 30
    let targetWidth: CGFloat = 640
    let jpegQuality: CGFloat = 0.50

    var targetFPS: Double {
        lock.lock(); defer { lock.unlock() }
        return requestedFPS
    }

    func setTargetFPS(_ fps: Double) {
        lock.lock()
        requestedFPS = min(60, max(30, fps))
        lock.unlock()
    }

    func submit(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (Data, Stats) -> Void
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let currentTarget = requestedFPS
        let minInterval = 1.0 / currentTarget
        if busy || now - lastSubmit < minInterval {
            lock.unlock()
            return
        }
        busy = true
        lastSubmit = now
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.busy = false
                self.lock.unlock()
            }

            var image = CIImage(cvPixelBuffer: pixelBuffer)
            image = image.oriented(forExifOrientation: Int32(orientation.rawValue))
            let extent = image.extent
            guard extent.width > 0, extent.height > 0 else { return }

            let scale = min(1.0, self.targetWidth / extent.width)
            if scale < 1.0 {
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            let outRect = image.extent.integral
            guard let cg = self.context.createCGImage(image, from: outRect) else { return }

            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(
                dest,
                cg,
                [kCGImageDestinationLossyCompressionQuality: self.jpegQuality] as CFDictionary
            )
            guard CGImageDestinationFinalize(dest) else { return }

            self.lock.lock()
            self.windowFrames += 1
            let t = CFAbsoluteTimeGetCurrent()
            let elapsed = t - self.windowStart
            if elapsed >= 1.0 {
                self.measuredFPS = Double(self.windowFrames) / elapsed
                self.windowFrames = 0
                self.windowStart = t
            }
            let fps = self.measuredFPS
            self.lock.unlock()

            completion(
                data as Data,
                Stats(fps: fps, width: cg.width, height: cg.height)
            )
        }
    }
}