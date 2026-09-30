import SwiftUI

struct FOVPreview: View {
    let radius: Double

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let scale = min(max(radius / 350.0, 0.18), 1.0)
            let diameter = side * scale

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.55))

                Circle()
                    .stroke(
                        RavenTheme.accent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
                    .frame(width: diameter, height: diameter)

                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 18, height: 1)

                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1, height: 18)

                VStack {
                    HStack {
                        Text("FOV PREVIEW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(RavenTheme.textSecondary)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(height: 210)
    }
}
