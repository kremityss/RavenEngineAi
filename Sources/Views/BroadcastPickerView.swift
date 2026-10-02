import SwiftUI
import ReplayKit
import UIKit

private final class RavenSystemBroadcastPickerView: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()

        // RPSystemBroadcastPickerView keeps its internal UIButton at its
        // intrinsic size even when SwiftUI gives the outer view a large frame.
        // Stretch only Apple's actual picker button so the complete custom
        // Raven control becomes tappable.
        for case let button as UIButton in subviews {
            button.frame = bounds
            button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.isUserInteractionEnabled = true
        }
    }
}

struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RavenSystemBroadcastPickerView(frame: .zero)
        configure(picker)
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        configure(uiView)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }

    private func configure(_ picker: RPSystemBroadcastPickerView) {
        picker.preferredExtension = "com.kremcheats.RavenEngineAI.broadcast"
        picker.showsMicrophoneButton = false
        picker.tintColor = .clear
        picker.backgroundColor = .clear
        picker.isUserInteractionEnabled = true
        picker.clipsToBounds = true
    }
}
