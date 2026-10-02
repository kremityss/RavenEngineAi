import Foundation
import Network

final class RavenLiveServer {
    private let queue = DispatchQueue(label: "Raven.LiveServer", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var latestFrame = Data()
    private var latestState = Data(#"{"inference_location":"iphone","ready":false}"#.utf8)
    private var lastFrameRequest = Date.distantPast
    var onConfig: (([String: Any]) -> Void)?

    var wantsFrames: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastFrameRequest) < 2.0
    }

    func start(port: UInt16 = 8788) {
        stop()
        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        do {
            let l = try NWListener(using: .tcp, on: p)
            listener = l
            l.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            l.stateUpdateHandler = { state in
                if case .failed(let e) = state { print("RavenLiveServer failed: \(e)") }
            }
            l.start(queue: queue)
        } catch {
            print("RavenLiveServer start error: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func updateFrame(_ data: Data) {
        lock.lock()
        latestFrame = data
        lock.unlock()
    }

    func updateState(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        lock.lock()
        latestState = data
        lock.unlock()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            self.handle(data, connection: connection)
        }
    }

    private func handle(_ requestData: Data, connection: NWConnection) {
        let request = String(data: requestData, encoding: .utf8) ?? ""
        let first = request.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if method == "GET" && path.hasPrefix("/api/state") {
            lock.lock(); let body = latestState; lock.unlock()
            send(connection, status: "200 OK", type: "application/json", body: body)
            return
        }

        if method == "GET" && path.hasPrefix("/frame.jpg") {
            lock.lock()
            lastFrameRequest = Date()
            let body = latestFrame
            lock.unlock()
            guard !body.isEmpty else {
                send(connection, status: "404 Not Found", type: "text/plain", body: Data())
                return
            }
            send(connection, status: "200 OK", type: "image/jpeg", body: body)
            return
        }

        if method == "POST" && path.hasPrefix("/api/config") {
            if let range = request.range(of: "\r\n\r\n") {
                let body = String(request[range.upperBound...])
                if let data = body.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    onConfig?(obj)
                }
            }
            let body = Data(#"{"ok":true}"#.utf8)
            send(connection, status: "200 OK", type: "application/json", body: body)
            return
        }

        let body = Data("RavenEngineAI iPhone runtime".utf8)
        send(connection, status: "200 OK", type: "text/plain", body: body)
    }

    private func send(_ connection: NWConnection, status: String, type: String, body: Data) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(type)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store, no-cache, must-revalidate\r\n"
        header += "Connection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}