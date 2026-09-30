import SwiftUI

struct ESP32View: View {
    @EnvironmentObject private var ble: RavenBLEManager
    @EnvironmentObject private var wifi: RavenWiFiClient

    var body: some View {
        NavigationStack {
            ZStack {
                RavenTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        RavenCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("RavenLink BLE", systemImage: "wave.3.right")
                                        .font(.headline)
                                    Spacer()
                                    Text(ble.state.rawValue)
                                        .foregroundStyle(RavenTheme.textSecondary)
                                }
                                HStack {
                                    Button("SCAN") { ble.startScan() }
                                        .buttonStyle(.borderedProminent)
                                        .tint(RavenTheme.accent)
                                    Button("PING") { ble.sendPing() }
                                        .buttonStyle(.bordered)
                                        .disabled(ble.state != .connected)
                                }
                                if let ping = ble.lastPingMs {
                                    Text(String(format: "Last response %.2f ms", ping))
                                        .font(.caption)
                                        .foregroundStyle(RavenTheme.textSecondary)
                                }
                            }
                        }

                        if !ble.devices.isEmpty {
                            RavenCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("DISCOVERED").font(.caption.bold())
                                    ForEach(ble.devices) { device in
                                        Button {
                                            ble.connect(device)
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    Text(device.name).foregroundStyle(.primary)
                                                    Text(device.id.uuidString)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text("\(device.rssi) dBm")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        RavenCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("RavenLink Wi-Fi", systemImage: "wifi")
                                    .font(.headline)
                                TextField("Host", text: $wifi.host)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                HStack {
                                    Text("UDP \(wifi.port)")
                                    Spacer()
                                    Text(wifi.status).foregroundStyle(RavenTheme.textSecondary)
                                }
                                HStack {
                                    Button("CONNECT") { wifi.connect() }
                                        .buttonStyle(.borderedProminent)
                                        .tint(RavenTheme.accent)
                                    Button("DISCONNECT") { wifi.disconnect() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("ESP32-S3")
        }
    }
}
