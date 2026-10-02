import Foundation
import CoreBluetooth

final class RavenBLEOutput: NSObject {
    enum State: String {
        case unavailable, scanning, connecting, connected
    }

    static let serviceUUID = CBUUID(string: "7F8A0001-7D8E-4A31-9D4A-524156454E01")
    static let commandUUID = CBUUID(string: "7F8A0002-7D8E-4A31-9D4A-524156454E01")

    private let queue = DispatchQueue(label: "Raven.Broadcast.BLE", qos: .userInteractive)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var sequence: UInt16 = 0
    private(set) var state: State = .unavailable

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
    func send(target: RavenAimTarget) {
        queue.async { [weak self] in
            guard let self,
                  self.state == .connected,
                  let peripheral = self.peripheral,
                  let command = self.command else { return }

            self.sequence &+= 1
            let dx = Int16(clamping: Int((target.dx * 32767.0).rounded()))
            let dy = Int16(clamping: Int((target.dy * 32767.0).rounded()))
            let confidence = UInt8(clamping: Int((target.confidence * 255.0).rounded()))
            let payload = self.makePacket(sequence: self.sequence, dx: dx, dy: dy, confidence: confidence)

            let type: CBCharacteristicWriteType = command.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
            peripheral.writeValue(payload, for: command, type: type)
        }
    }

    private func scan() {
        command = nil
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func makePacket(sequence: UInt16, dx: Int16, dy: Int16, confidence: UInt8) -> Data {
        var bytes: [UInt8] = [0x52, 0x56, 0x01, 0x10]
        appendLE(sequence, to: &bytes)
        appendLE(UInt16(bitPattern: dx), to: &bytes)
        appendLE(UInt16(bitPattern: dy), to: &bytes)
        bytes.append(confidence)
        bytes.append(0x01)
        bytes.append(bytes.reduce(0, ^))
        return Data(bytes)
    }

    private func appendLE(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0x00FF))
        bytes.append(UInt8((value >> 8) & 0x00FF))
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
