import SwiftUI
import ReplayKit

struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.kremcheats.RavenEngineAI.broadcast"
        picker.showsMicrophoneButton = false
        picker.tintColor = .clear
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = "com.kremcheats.RavenEngineAI.broadcast"
        uiView.showsMicrophoneButton = false
        uiView.tintColor = .clear
        uiView.backgroundColor = .clear
    }
}
