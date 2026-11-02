import SwiftUI

struct InvestigationControlStrip: View {
    let isSLSEnabled: Bool
    let usesFrontCamera: Bool
    let savesVideo: Bool
    let filterMode: CameraFilterMode
    let cameraAvailable: Bool
    let onSLS: () -> Void
    let onCamera: () -> Void
    let onVideo: () -> Void
    let onFilter: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HUDControl(title: "SLS", icon: "figure.stand", active: isSLSEnabled, enabled: cameraAvailable, action: onSLS)
            HUDControl(title: usesFrontCamera ? "FRONT" : "REAR", icon: "camera.rotate", active: usesFrontCamera, enabled: cameraAvailable, action: onCamera)
            HUDControl(title: filterMode.title, icon: "camera.filters", active: filterMode != .normal, enabled: cameraAvailable, action: onFilter)
            HUDControl(title: "VIDEO", icon: "record.circle", active: savesVideo, enabled: cameraAvailable, action: onVideo)
        }
    }
}

private struct HUDControl: View {
    let title: LocalizedStringKey
    let icon: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.system(.caption2, design: .monospaced, weight: .bold)).lineLimit(1).minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(active ? NecroTheme.accent : .white)
            .background(active ? NecroTheme.accent.opacity(0.12) : NecroTheme.raisedPanel, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(active ? NecroTheme.accent : NecroTheme.border) }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
    }
}

struct InvestigationActions: View {
    let isRunning: Bool
    let onToggleSession: () -> Void
    let onSpiritBox: () -> Void
    let onEVP: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ToolButton(title: "SPIRIT BOX", subtitle: "RADIO SWEEP", icon: "dot.radiowaves.left.and.right", action: onSpiritBox)
            Button(action: onToggleSession) {
                VStack(spacing: 4) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill").font(.title2)
                    Text(LocalizedStringKey(isRunning ? "STOP" : "START")).font(.caption.weight(.black)).tracking(1.5)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(isRunning ? Color.white : Color.black)
                .background(isRunning ? NecroTheme.danger : NecroTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            ToolButton(title: "EVP", subtitle: "RECORDER", icon: "waveform", action: onEVP)
        }
    }
}

private struct ToolButton: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.title3).foregroundStyle(NecroTheme.accent)
                Text(title).font(.caption2.weight(.black))
                Text(subtitle).font(.caption2).foregroundStyle(NecroTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(.white)
            .necroPanel()
        }
        .buttonStyle(.plain)
    }
}
