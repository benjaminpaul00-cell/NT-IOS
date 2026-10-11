import SwiftUI

struct InvestigationHeader: View {
    let duration: String
    let isRunning: Bool
    let onHistory: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HeaderButton(icon: "list.bullet.rectangle", label: "Session history", action: onHistory)
            VStack(spacing: 3) {
                Text("NecroTube")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .italic()
                    .foregroundStyle(.white)
                    .shadow(color: NecroTheme.accent.opacity(0.8), radius: 8)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Circle().fill(isRunning ? NecroTheme.accent : NecroTheme.muted).frame(width: 6, height: 6)
                    Text(isRunning ? "INVESTIGATION ACTIVE" : "SYSTEM STANDBY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(isRunning ? NecroTheme.accent : NecroTheme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            HeaderButton(icon: "gearshape.fill", label: "Settings", action: onSettings)
        }
        .foregroundStyle(.white)
        .overlay(alignment: .bottomTrailing) {
            Text(duration)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(NecroTheme.gold)
                .offset(y: 7)
        }
    }
}

private struct HeaderButton: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 42, height: 42)
        }
        .accessibilityLabel(label)
    }
}
