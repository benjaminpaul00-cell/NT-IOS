import SwiftUI

struct InvestigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    @ObservedObject var state: InvestigationState
    @State private var showsCameraSettings = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CameraScannerPanel(
                    camera: state.camera,
                    availability: state.cameraAvailability,
                    isSLSEnabled: state.isSLSEnabled,
                    filterMode: state.filterMode
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.76), .clear, .black.opacity(0.20), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                ScannerBrackets().ignoresSafeArea()

                ScaledInvestigationHUD(
                    availableSize: proxy.size,
                    state: state,
                    onHistory: { appState.presentedRoute = .history },
                    onMap: {
                        if let url = URL(string: "https://www.necrotube.com/haunted-map") { openURL(url) }
                    },
                    onShop: {
                        if let url = URL(string: "https://www.necrotube.com/store") { openURL(url) }
                    },
                    onSettings: { appState.presentedRoute = .settings },
                    onSpiritBox: { appState.presentedRoute = .spiritBox },
                    onEVP: { appState.presentedRoute = .evpRecorder },
                    onCameraSettings: { showsCameraSettings = true }
                )
            }
        }
        .background(.black)
        .toolbar(.hidden, for: .navigationBar)
        .task { await state.startCamera() }
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .active {
                    await state.startCamera()
                } else {
                    await state.stopCamera()
                }
            }
        }
        .onDisappear { Task { await state.stopCamera() } }
        .sheet(isPresented: $showsCameraSettings) {
            CameraSettingsSheet(state: state)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .alert("Enregistrement sauvegardé", isPresented: Binding(
            get: { state.confirmationMessage != nil },
            set: { if !$0 { state.confirmationMessage = nil } }
        )) {
            Button("OK") { state.confirmationMessage = nil }
        } message: {
            Text(state.confirmationMessage ?? "")
        }
        .alert("Erreur", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

private struct ScaledInvestigationHUD: View {
    let availableSize: CGSize
    @ObservedObject var state: InvestigationState
    let onHistory: () -> Void
    let onMap: () -> Void
    let onShop: () -> Void
    let onSettings: () -> Void
    let onSpiritBox: () -> Void
    let onEVP: () -> Void
    let onCameraSettings: () -> Void

    var body: some View {
        let scale = min(availableSize.width / 360, availableSize.height / 760)
        InvestigationHUDCanvas(
            state: state,
            onHistory: onHistory,
            onMap: onMap,
            onShop: onShop,
            onSettings: onSettings,
            onSpiritBox: onSpiritBox,
            onEVP: onEVP,
            onCameraSettings: onCameraSettings
        )
        .frame(width: 360, height: 760)
        .scaleEffect(scale)
        .frame(width: availableSize.width, height: availableSize.height)
    }
}

private struct InvestigationHUDCanvas: View {
    @ObservedObject var state: InvestigationState
    let onHistory: () -> Void
    let onMap: () -> Void
    let onShop: () -> Void
    let onSettings: () -> Void
    let onSpiritBox: () -> Void
    let onEVP: () -> Void
    let onCameraSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HUDHeader(
                onHistory: onHistory,
                onMap: onMap,
                onShop: onShop,
                onSettings: onSettings
            )
            .frame(height: 68)

            ScannerActiveLabel()
                .padding(.top, 5)

            HStack(alignment: .top) {
                EMFCard(value: state.magneticDelta)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    SensorStatusCard(sensorActive: state.sensorAvailability == .active)
                    RecordingButton(
                        isRecording: state.savesVideo,
                        action: state.toggleVideoRecording
                    )
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            ListeningReadout(
                isRunning: state.isSessionRunning,
                output: state.output,
                audioLevel: state.audioLevel,
                audioAvailable: state.audioAvailability != .unavailable
            )
            RecentWordsCard(words: state.recentWords, action: onHistory)
                .padding(.top, 9)

            HStack(spacing: 8) {
                HUDActionCard(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "SPIRIT BOX",
                    subtitle: "COMMUNICATION",
                    color: NecroTheme.accent,
                    action: onSpiritBox
                )
                SessionToggleCard(isRunning: state.isSessionRunning, action: state.toggleSession)
                HUDActionCard(
                    icon: "mic.fill",
                    title: "EVP RECORDER",
                    subtitle: "RECORD & ANALYZE",
                    color: .white,
                    action: onEVP
                )
            }
            .frame(height: 110)
            .padding(.top, 9)

            HStack(spacing: 8) {
                HUDWideButton(
                    icon: "viewfinder",
                    title: "SLS MODE",
                    subtitle: state.isSLSEnabled ? "VISUAL TRACKING ON" : "VISUAL TRACKING",
                    active: state.isSLSEnabled,
                    action: { state.setSLS(!state.isSLSEnabled) }
                )
                HUDWideButton(
                    icon: "camera.fill",
                    title: "CAMERA MODES",
                    subtitle: "NIGHT VISION • SPECTRAL • FILTERS",
                    widthWeight: 1.2,
                    action: onCameraSettings
                )
            }
            .frame(height: 57)
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct HUDHeader: View {
    let onHistory: () -> Void
    let onMap: () -> Void
    let onShop: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HUDSquare(icon: "line.3.horizontal", color: .white, action: onHistory)
            Button {
                if let url = URL(string: "https://necrotube.com/") {
                    UIApplication.shared.open(url)
                }
            } label: {
                NecroTubeLogo()
                    .frame(width: 104, height: 52)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 10)
            HUDSquare(icon: "globe.americas.fill", color: NecroTheme.accent, action: onMap)
            Spacer().frame(width: 6)
            HUDSquare(icon: "bag.fill", color: NecroTheme.gold, action: onShop)
            Spacer().frame(width: 6)
            HUDSquare(icon: "gearshape.fill", color: .white, action: onSettings)
        }
    }
}

private struct HUDSquare: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
        }
        .background(NecroTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(NecroTheme.border, lineWidth: 1) }
    }
}

private struct ScannerActiveLabel: View {
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(NecroTheme.accent).frame(width: 7, height: 7)
            Text("MAG-SCANNER ACTIVE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
            Circle().fill(NecroTheme.accent).frame(width: 7, height: 7)
        }
        .foregroundStyle(NecroTheme.accent)
        .frame(maxWidth: .infinity)
    }
}

private struct EMFCard: View {
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("EMF")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1)
            HStack(alignment: .bottom, spacing: 0) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 29, weight: .black, design: .monospaced))
                Text(" µT")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.bottom, 5)
            }
            .foregroundStyle(NecroTheme.accent)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Rectangle()
                        .fill(NecroTheme.accent.opacity(index == 0 ? 1 : 0.18))
                        .frame(height: CGFloat(6 + index * 3))
                }
            }
            .frame(height: 25)
            Text("LOW ACTIVITY")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(11)
        .frame(width: 132, height: 119, alignment: .topLeading)
        .background(NecroTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(NecroTheme.border) }
    }
}

private struct SensorStatusCard: View {
    let sensorActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "sensor.fill")
                    .font(.system(size: 18))
                Text("SENSORS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            Divider().overlay(NecroTheme.border)
            HStack(spacing: 7) {
                Image(systemName: "wifi").font(.system(size: 19))
                Text(sensorActive ? "STABLE" : "STANDBY")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .foregroundStyle(NecroTheme.accent)
        .padding(11)
        .frame(width: 132, height: 79, alignment: .leading)
        .background(NecroTheme.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(NecroTheme.border) }
    }
}

private struct RecordingButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "circle.fill").font(.system(size: 12))
                Text(isRecording ? " STOP" : " REC").font(.system(size: 8))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
        .foregroundStyle(isRecording ? NecroTheme.danger : .white)
        .background(
            isRecording ? NecroTheme.danger.opacity(0.25) : Color.black.opacity(0.75),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecording ? NecroTheme.danger : NecroTheme.border)
        }
    }
}

private struct ListeningReadout: View {
    let isRunning: Bool
    let output: String
    let audioLevel: Double?
    let audioAvailable: Bool

    var body: some View {
        VStack(spacing: 3) {
            if isRunning {
                WaveformStrip(level: audioLevel ?? 0)
                    .frame(width: 122, height: 28)
                Text("LISTENING...")
                    .font(.system(size: 14, design: .monospaced))
                    .tracking(5)
                Text(output == "— — —" ? "" : output)
                    .font(.system(size: 50, weight: .black, design: .monospaced))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: 340)
                    .frame(minHeight: 54)
                    .shadow(color: NecroTheme.accent.opacity(0.85), radius: 18)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                }
                if !audioAvailable {
                    Text("MICROPHONE UNAVAILABLE — SENSORS ACTIVE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(NecroTheme.gold)
                }
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .thin))
                Text("READY")
                    .font(.system(size: 17, design: .monospaced))
                    .tracking(5)
            }
        }
        .foregroundStyle(NecroTheme.accent)
        .frame(maxWidth: .infinity)
    }
}

private struct WaveformStrip: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<24, id: \.self) { index in
                let pattern = Double((index * 7) % 11) / 10
                RoundedRectangle(cornerRadius: 1)
                    .fill(NecroTheme.accent)
                    .frame(width: 3, height: max(3, min(27, 3 + level * 21 + pattern * 9)))
            }
        }
    }
}

private struct RecentWordsCard: View {
    let words: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("RECENT WORDS")
                    .font(.system(size: 8))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.65))
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Text(words.indices.contains(index) ? words[index] : "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(
                                words.indices.contains(index)
                                    ? NecroTheme.accent
                                    : .white.opacity(0.35)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
        }
        .frame(width: 259)
        .frame(minHeight: 49)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(NecroTheme.border) }
    }
}

private struct HUDActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 28, weight: .semibold))
                Text(LocalizedStringKey(title))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 7, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(NecroTheme.accent)
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(NecroTheme.border) }
    }
}

private struct SessionToggleCard: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .stroke(isRunning ? NecroTheme.accent : .white, lineWidth: 2)
                        .frame(width: 59, height: 59)
                    Image(systemName: isRunning ? "stop.fill" : "mic.fill")
                        .font(.system(size: 31))
                }
                Text(LocalizedStringKey(isRunning ? "STOP" : "START"))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(2)
                Text(LocalizedStringKey(isRunning ? "LISTENING" : "READY"))
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(isRunning ? NecroTheme.accent : .white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isRunning ? NecroTheme.accent : NecroTheme.border, lineWidth: isRunning ? 2 : 1)
        }
    }
}

private struct HUDWideButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var active = false
    var widthWeight: CGFloat = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(active ? NecroTheme.accent : .white)
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 6.5, design: .monospaced))
                        .foregroundStyle(NecroTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(active ? NecroTheme.accent : NecroTheme.border) }
        .frame(width: widthWeight > 1 ? 178 : 150)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct CameraSettingsSheet: View {
    @ObservedObject var state: InvestigationState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("CAMERA SETTINGS")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundStyle(NecroTheme.accent)
                CameraSettingsSection(title: "CAMERA SETTINGS") {
                    CameraToggle(title: "CAMERA SENSORS", isOn: Binding(
                        get: { state.camera.isRunning },
                        set: { enabled in
                            Task {
                                if enabled { await state.startCamera() }
                                else { await state.stopCamera() }
                            }
                        }
                    ))
                    CameraToggle(title: "SLS MODE", isOn: Binding(
                        get: { state.isSLSEnabled },
                        set: state.setSLS
                    ))
                }
                CameraSettingsSection(title: "CAMERA MODES") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 8) {
                        ForEach(CameraFilterMode.allCases) { mode in
                            Button {
                                state.filterMode = mode
                            } label: {
                                Text(mode.title)
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .foregroundStyle(state.filterMode == mode ? .black : .white)
                            .background(
                                state.filterMode == mode ? NecroTheme.accent : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(NecroTheme.border) }
                        }
                    }
                }
                CameraSettingsSection(title: "CAMERA") {
                    CameraToggle(title: "FRONT CAMERA", isOn: Binding(
                        get: { state.usesFrontCamera },
                        set: { _ in state.switchCamera() }
                    ))
                }
                CameraRecordingsSection(camera: state.camera)
                if case .unavailable = state.cameraAvailability {
                    Text("PHYSICAL CAMERA UNAVAILABLE ON THIS SIMULATOR")
                        .font(.caption.monospaced())
                        .foregroundStyle(NecroTheme.gold)
                }
            }
            .padding(24)
        }
        .foregroundStyle(.white)
        .background(.black)
    }
}

private struct CameraRecordingsSection: View {
    @ObservedObject var camera: CameraSLSService
    @State private var recordingToDelete: URL?

    var body: some View {
        CameraSettingsSection(title: "ENREGISTREMENTS") {
            if camera.recentRecordings.isEmpty {
                Text("Aucun enregistrement")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(camera.recentRecordings, id: \.self) { recording in
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundStyle(NecroTheme.accent)
                        Text(recording.lastPathComponent)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                        Spacer()
                        ShareLink(item: recording) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            recordingToDelete = recording
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Supprimer cette vidéo de l’application ?",
            isPresented: Binding(
                get: { recordingToDelete != nil },
                set: { if !$0 { recordingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                guard let recordingToDelete else { return }
                try? camera.deleteRecording(at: recordingToDelete)
                self.recordingToDelete = nil
            }
            Button("Annuler", role: .cancel) {
                recordingToDelete = nil
            }
        }
    }
}

private struct CameraSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.08)) }
    }
}

private struct CameraToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(.body.monospaced())
            .tint(NecroTheme.accent)
    }
}
