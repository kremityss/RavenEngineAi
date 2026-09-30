import Foundation
import CoreBluetooth

enum RavenLink {
    static let serviceUUID = CBUUID(string: "7F8A0001-7D8E-4A31-9D4A-524156454E01")
    static let commandUUID = CBUUID(string: "7F8A0002-7D8E-4A31-9D4A-524156454E01")
    static let telemetryUUID = CBUUID(string: "7F8A0003-7D8E-4A31-9D4A-524156454E01")
    static let protocolVersion = 1
}

enum RavenMessageType: String, Codable {
    case hello, heartbeat, ping, deviceInfo, config, telemetry
}

struct RavenPacket: Codable {
    let version: Int
    let type: RavenMessageType
    let sequence: UInt32
    let timestampMs: UInt64
    let payload: [String: String]

    static func ping(sequence: UInt32) -> RavenPacket {
        RavenPacket(
            version: RavenLink.protocolVersion,
            type: .ping,
            sequence: sequence,
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: [:]
        )
    }

    func encoded() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }
}
