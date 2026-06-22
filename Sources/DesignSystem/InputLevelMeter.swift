import SwiftUI

struct InputLevelMeter: View {
    let level: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "input.title", defaultValue: "Input level"))
                .font(.subheadline.weight(.semibold))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(8, proxy.size.width * CGFloat(level)))
                }
            }
            .frame(height: 10)
            .accessibilityIdentifier(A11yID.inputLevel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "input.a11y", defaultValue: "Microphone input level"))
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}
