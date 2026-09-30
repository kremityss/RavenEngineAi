import Foundation
import QuartzCore
import UIKit

@MainActor
final class RavenDiagnostics: NSObject, ObservableObject {
    @Published var uiFPS: Double = 0
    @Published var thermalState = "Nominal"
    @Published var deviceName = UIDevice.current.model
    @Published var systemVersion = UIDevice.current.systemVersion
    @Published var physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    private var displayLink: CADisplayLink?
    private var frames = 0
    private var lastSample = CACurrentMediaTime()

    override init() {
        super.init()
        start()
    }

    deinit { displayLink?.invalidate() }

    private func start() {
        displayLink = CADisplayLink(target: self, selector: #selector(frameTick))
        displayLink?.add(to: .main, forMode: .common)
        refreshThermals()
    }

    @objc private func frameTick() {
        frames += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastSample
        guard elapsed >= 1 else { return }
        uiFPS = Double(frames) / elapsed
        frames = 0
        lastSample = now
        refreshThermals()
    }

    private func refreshThermals() {
        thermalState = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
