import Foundation
import CoreBluetooth

final class RavenBLEOutput: NSObject {
    enum State: String {
        case unavailable, scanning, connecting, connected
    }

    // Match the ESP32-S3 firmware already flashed on the Raven N16R8 board.
    static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    static let commandUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

    private let queue = DispatchQueue(label: "Raven.Broadcast.BLE", qos: .userInteractive)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private(set) var state: State = .unavailable

    // Mirrors the working AScript controller defaults.
    private var strength: Double = 0.72
    private var sensitivityX: Double = 0.42
    private var sensitivityY: Double = 0.42
    private var maxStepXRatio: Double = 0.045
    private var maxStepYRatio: Double = 0.095
    private var swipeMs: Int = 45
    private var lookAnchorX: Double = 0.78
    private var lookAnchorY: Double = 0.50

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            self.scan()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.central.stopScan()
            if let peripheral = self.peripheral {
                self.central.cancelPeripheralConnection(peripheral)
            }
            self.peripheral = nil
            self.command = nil
        }
    }

    func updateSettings(_ payload: [String: Any]) {
        queue.async { [weak self] in
            guard let self else { return }
            if let v = payload["strength"] as? NSNumber {
                self.strength = max(0.05, min(1.0, v.doubleValue))
            }
            if let v = payload["sensitivity_x"] as? NSNumber {
                self.sensitivityX = max(0.05, min(1.5, v.doubleValue))
            }
            if let v = payload["sensitivity_y"] as? NSNumber {
                self.sensitivityY = max(0.05, min(1.5, v.doubleValue))
            }
            if let v = payload["swipe_ms"] as? NSNumber {
                self.swipeMs = max(5, min(120, v.intValue))
            }
            if let v = payload["look_anchor_x"] as? NSNumber {
                self.lookAnchorX = max(0.55, min(0.95, v.doubleValue))
            }
            if let v = payload["look_anchor_y"] as? NSNumber {
                self.lookAnchorY = max(0.20, min(0.80, v.doubleValue))
            }
        }
    }

    func send(target: RavenAimTarget) {
        queue.async { [weak self] in
            guard let self,
                  self.state == .connected,
                  let peripheral = self.peripheral,
                  let command = self.command else { return }

            // The flashed firmware accepts ASCII ABS swipe commands:
            //   slide x0 y0 x1 y1 durationMs
            // Convert the normalized aim error into the same look-anchor motion
            // used by the working AScript controller.
            let gainX = self.strength * self.sensitivityX
            let gainY = self.strength * self.sensitivityY
            let stepX = max(-self.maxStepXRatio, min(self.maxStepXRatio, target.dx * gainX))
            let stepY = max(-self.maxStepYRatio, min(self.maxStepYRatio, target.dy * gainY))

            let ax = self.hid(self.lookAnchorX)
            let ay = self.hid(self.lookAnchorY)
            let bx = self.hid(self.lookAnchorX + stepX)
            let by = self.hid(self.lookAnchorY + stepY)

            let text = "slide \(ax) \(ay) \(bx) \(by) \(self.swipeMs)"
            let payload = Data(text.utf8)
            let type: CBCharacteristicWriteType = command.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
            peripheral.writeValue(payload, for: command, type: type)
        }
    }

    private func hid(_ normalized: Double) -> Int {
        Int((max(0.0, min(1.0, normalized)) * 32767.0).rounded())
    }

    private func scan() {
        command = nil
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

extension RavenBLEOutput: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            state = .unavailable
            return
        }
        scan()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        guard self.peripheral == nil else { return }
        state = .connecting
        self.peripheral = peripheral
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        scan()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        command = nil
        scan()
    }
}

extension RavenBLEOutput: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.commandUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.commandUUID }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        command = characteristic
        state = .connected
    }
}
