import SwiftUI

struct ConfidenceMeter: View {
    let confidence: Double
    let showsValue: Bool

    private var label: String {
        let percent = Int((confidence * 100).rounded())
        if confidence < 0.15 {
            return String(localized: "confidence.low", defaultValue: "Low confidence")
        }
        if confidence < 0.45 {
            return String(localized: "confidence.moderate", defaultValue: "Moderate confidence")
        }
        return String(localized: "confidence.high", defaultValue: "High confidence")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "confidence.title", defaultValue: "Analysis confidence"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if showsValue {
                    Text("\(Int((confidence * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Gauge(value: confidence, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                Text(label)
                    .font(.caption)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(confidenceTint)
            Text(String(
                localized: "confidence.caption",
                defaultValue: "Higher confidence means the beat pattern was clearer."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((confidence * 100).rounded())) percent")
        .accessibilityIdentifier(A11yID.confidenceMeter)
    }

    private var confidenceTint: Color {
        if confidence < 0.15 { return .orange }
        if confidence < 0.45 { return .yellow }
        return .green
    }
}
