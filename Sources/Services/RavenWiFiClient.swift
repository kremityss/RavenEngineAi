import Foundation
import Network

@MainActor
final class RavenWiFiClient: ObservableObject {
    @Published var status = "Disconnected"
    @Published var host = "192.168.4.1"
    @Published var port: UInt16 = 7878

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "RavenLink.WiFi", qos: .userInitiated)

    func connect() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            status = "Invalid port"
            return
        }

        connection?.cancel()
        let next = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection = next
        status = "Connecting"

        next.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.status = "Connected"
                case .failed(let error): self?.status = "Failed: \(error.localizedDescription)"
                case .cancelled: self?.status = "Disconnected"
                default: break
                }
            }
        }
        next.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        status = "Disconnected"
    }

    func send(_ packet: RavenPacket) {
        guard let data = try? packet.encoded() else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }
}
