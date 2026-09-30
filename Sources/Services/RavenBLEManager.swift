import Foundation
import CoreBluetooth
import QuartzCore

struct RavenDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

@MainActor
final class RavenBLEManager: NSObject, ObservableObject {
    enum LinkState: String {
        case unavailable = "Unavailable"
        case idle = "Idle"
        case scanning = "Scanning"
        case connecting = "Connecting"
        case connected = "Connected"
    }

    @Published var state: LinkState = .idle
    @Published var devices: [RavenDevice] = []
    @Published var connectedName = "None"
    @Published var lastMessage = "No telemetry"
    @Published var lastPingMs: Double?

    private var central: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var pingStartedAt: CFTimeInterval?
    private var sequence: UInt32 = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            state = .unavailable
            return
        }
        devices.removeAll()
        state = .scanning
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ device: RavenDevice) {
        stopScan()
        state = .connecting
        activePeripheral = device.peripheral
        central.connect(device.peripheral)
    }

    func disconnect() {
        guard let activePeripheral else { return }
        central.cancelPeripheralConnection(activePeripheral)
    }

    func sendPing() {
        guard let peripheral = activePeripheral,
              let characteristic = commandCharacteristic else { return }
        sequence &+= 1
        guard let data = try? RavenPacket.ping(sequence: sequence).encoded() else { return }
        pingStartedAt = CACurrentMediaTime()
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }
}

extension RavenBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state == .poweredOn ? .idle : .unavailable
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "ESP32-S3"
        guard name.localizedCaseInsensitiveContains("raven")
                || name.localizedCaseInsensitiveContains("esp32") else { return }

        let device = RavenDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        connectedName = peripheral.name ?? "RavenLink"
        peripheral.delegate = self
        peripheral.discoverServices([RavenLink.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        state = .idle
        connectedName = "None"
        commandCharacteristic = nil
        activePeripheral = nil
    }
}

extension RavenBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics(
                [RavenLink.commandUUID, RavenLink.telemetryUUID],
                for: $0
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == RavenLink.commandUUID {
                commandCharacteristic = characteristic
            }
            if characteristic.uuid == RavenLink.telemetryUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        lastMessage = String(data: data, encoding: .utf8) ?? "\(data.count) bytes"
        if let pingStartedAt {
            lastPingMs = (CACurrentMediaTime() - pingStartedAt) * 1000
            self.pingStartedAt = nil
        }
    }
}
