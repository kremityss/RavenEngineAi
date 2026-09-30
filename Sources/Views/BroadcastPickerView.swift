import SwiftUI
import ReplayKit

struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.kremcheats.RavenEngineAI.broadcast"
        picker.showsMicrophoneButton = false
        picker.tintColor = .white
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
