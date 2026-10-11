import SwiftUI

struct SpiritOutputPanel: View {
    let output: String
    let magneticDelta: Double?
    let audioLevel: Double?

    var body: some View {
        VStack(spacing: 8) {
            Text("SPIRIT COMMUNICATION")
                .font(.caption2.weight(.black))
                .tracking(2)
                .foregroundStyle(NecroTheme.gold)
            Text(output)
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 34)
            HStack {
                MetricView(title: "EMF DELTA", value: magneticDelta.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "µT", available: magneticDelta != nil)
                Divider().overlay(NecroTheme.border)
                MetricView(title: "AUDIO LEVEL", value: audioLevel.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", unit: "", available: audioLevel != nil)
            }
            .frame(height: 42)
        }
        .padding(12)
        .necroPanel()
    }
}

private struct MetricView: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String
    let available: Bool
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(NecroTheme.muted)
            Text(verbatim: unit.isEmpty ? value : "\(value) \(unit)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(available ? NecroTheme.accent : NecroTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}
