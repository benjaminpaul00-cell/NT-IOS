import SwiftUI

struct CameraScannerPanel: View {
    @ObservedObject var camera: CameraSLSService
    let availability: HardwareAvailability
    let isSLSEnabled: Bool
    let filterMode: CameraFilterMode

    var body: some View {
        ZStack {
            Color.black
            if camera.isRunning {
                CameraPreview(session: camera.session)
                CameraVisualFilter(mode: filterMode)
                if isSLSEnabled {
                    SkeletonOverlay(segments: camera.skeletonSegments)
                }
            } else {
                CameraOfflineStatus(availability: availability)
            }
            ScannerGrid().opacity(0.28)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CameraVisualFilter: View {
    let mode: CameraFilterMode

    var body: some View {
        switch mode {
        case .normal:
            Color.clear
        case .nightVision:
            ZStack {
                Color.green.opacity(0.25).blendMode(.color)
                ScanLines().opacity(0.22)
            }
        case .thermal:
            LinearGradient(
                colors: [.blue.opacity(0.42), .purple.opacity(0.25), .red.opacity(0.38), .yellow.opacity(0.2)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .blendMode(.color)
        case .spectral:
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.32), .cyan.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.color)
                ScanLines().opacity(0.3)
            }
        }
    }
}

private struct ScanLines: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 0.0, through: size.height, by: 5.0) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.black), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CameraOfflineStatus: View {
    let availability: HardwareAvailability

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 42, weight: .thin))
            Text(title)
                .font(.caption.monospaced().weight(.bold))
                .multilineTextAlignment(.center)
            if availability == .unavailable {
                Text("The iOS Simulator does not provide a physical camera. Use an iPhone for video and SLS.")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .foregroundStyle(NecroTheme.accent)
        .padding(.bottom, 150)
    }

    private var title: LocalizedStringKey {
        switch availability {
        case .unavailable: "PHYSICAL CAMERA UNAVAILABLE"
        case .permissionRequired: "CAMERA PERMISSION REQUIRED"
        case .ready: "OPTICAL SENSORS READY"
        case .active: "OPTICAL SENSORS ACTIVE"
        case .failed: "CAMERA ERROR"
        }
    }
}

struct ScannerGrid: View {
    var body: some View {
        Canvas { context, size in
            let color = NecroTheme.accent.opacity(0.15)
            for column in 1..<8 {
                let x = size.width * CGFloat(column) / 8
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
            for row in 1..<14 {
                let y = size.height * CGFloat(row) / 14
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ScannerBrackets: View {
    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 24
            let length: CGFloat = 40
            var path = Path()
            path.move(to: CGPoint(x: inset, y: inset + length))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + length, y: inset))
            path.move(to: CGPoint(x: size.width - inset - length, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: inset + length))
            path.move(to: CGPoint(x: inset, y: size.height - inset - length))
            path.addLine(to: CGPoint(x: inset, y: size.height - inset))
            path.addLine(to: CGPoint(x: inset + length, y: size.height - inset))
            path.move(to: CGPoint(x: size.width - inset - length, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - length))
            context.stroke(path, with: .color(NecroTheme.accent.opacity(0.75)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}
