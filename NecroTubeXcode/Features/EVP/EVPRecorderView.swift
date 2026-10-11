import Foundation
import SwiftUI

struct EVPRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var audio: EVPAudioEngine
    let onOpen: () async -> Void
    let onClose: () async -> Void
    @State private var elapsedSeconds = 0
    @State private var recordings: [URL] = []
    @State private var recordingToDelete: URL?

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 360, proxy.size.height / 760)
            ZStack {
                Color.black.ignoresSafeArea()
                EVPCanvas(
                    audio: audio,
                    elapsedSeconds: elapsedSeconds,
                    recordings: recordings,
                    dismiss: { dismiss() },
                    toggleRecording: toggleRecording,
                    toggleWhiteNoise: toggleWhiteNoise,
                    requestDelete: { recordingToDelete = $0 }
                )
                .frame(width: 360, height: 760)
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await onOpen()
            recordings = audio.recentRecordings()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if audio.isRecording { elapsedSeconds += 1 }
            }
        }
        .alert("Audio Error", isPresented: Binding(
            get: { audio.errorMessage != nil },
            set: { if !$0 { audio.errorMessage = nil } }
        )) {
            Button("OK") { audio.errorMessage = nil }
        } message: {
            Text(audio.errorMessage ?? "")
        }
        .confirmationDialog(
            "Supprimer cet enregistrement EVP ?",
            isPresented: Binding(
                get: { recordingToDelete != nil },
                set: { if !$0 { recordingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                guard let recordingToDelete else { return }
                do {
                    try audio.deleteRecording(at: recordingToDelete)
                    recordings = audio.recentRecordings()
                } catch {
                    audio.errorMessage = error.localizedDescription
                }
                self.recordingToDelete = nil
            }
            Button("Annuler", role: .cancel) {
                recordingToDelete = nil
            }
        }
        .onDisappear {
            Task {
                if audio.isRecording {
                    _ = try? await audio.stopEVPRecording()
                    AnalyticsManager.shared.logEVPRecordingFinished()
                }
                audio.stopWhiteNoise()
                await audio.stopLevelMonitoring()
                await onClose()
            }
        }
    }

    private func toggleRecording() {
        Task {
            do {
                if audio.isRecording {
                    _ = try await audio.stopEVPRecording()
                    AnalyticsManager.shared.logEVPRecordingFinished()
                    recordings = audio.recentRecordings()
                } else {
                    elapsedSeconds = 0
                    _ = try await audio.startEVPRecording()
                    AnalyticsManager.shared.logEVPRecordingStarted()
                }
            } catch {
                audio.errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleWhiteNoise(_ enabled: Bool) {
        Task {
            do {
                if enabled {
                    try await audio.startWhiteNoise()
                    AnalyticsManager.shared.logWhiteNoiseStarted()
                } else {
                    audio.stopWhiteNoise()
                }
            } catch {
                audio.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct EVPWaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0...24 {
            let x = rect.width * CGFloat(index) / 24
            let y = rect.midY + sin(CGFloat(index) * .pi / 3) * rect.height * 0.22
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

private struct EVPCanvas: View {
    @ObservedObject var audio: EVPAudioEngine
    let elapsedSeconds: Int
    let recordings: [URL]
    let dismiss: () -> Void
    let toggleRecording: () -> Void
    let toggleWhiteNoise: (Bool) -> Void
    let requestDelete: (URL) -> Void

    private let green = Color(red: 0, green: 0.91, blue: 0.48)
    private let border = Color.white.opacity(0.35)

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "arrow.left").font(.system(size: 24))
                        .frame(width: 46, height: 46)
                }
                Spacer()
                NecroTubeLogo().frame(width: 96, height: 46)
                Spacer()
                Spacer().frame(width: 46, height: 46)
            }
            .foregroundStyle(.white).padding(.horizontal, 12)

            HStack(spacing: 14) {
                Circle().fill(green).frame(width: 7, height: 7)
                Text("MAG-SCANNER ACTIVE")
                Circle().fill(green).frame(width: 7, height: 7)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(2).foregroundStyle(green).frame(height: 31)

            HStack {
                infoCard("AUDIO INPUT", audioInputStatus, color: audio.errorMessage == nil ? green : .red)
                Spacer()
                VStack(spacing: 3) {
                    HStack {
                        EVPWaveLine().stroke(green, lineWidth: 1).frame(width: 34, height: 8)
                        Text("EVP").font(.system(size: 17, weight: .bold, design: .monospaced))
                        EVPWaveLine().stroke(green, lineWidth: 1).frame(width: 34, height: 8)
                    }
                }
                Spacer()
                infoCard("SENSOR STATUS", "STABLE", color: .white)
            }
            .padding(.horizontal, 12).frame(height: 64)

            Text(timeText)
                .font(.system(size: 33, weight: .medium, design: .monospaced))
                .foregroundStyle(green)
            Text(LocalizedStringKey(audio.isRecording ? "RECORDING" : "READY TO RECORD"))
                .font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(.gray)

            EVPWaveLine().stroke(green, lineWidth: 1.3).frame(height: 39).padding(.horizontal, 12)

            HStack {
                stat("PVE MODE", "OFF")
                stat("MIC GAIN", String(format: "%.1fx", audio.softwareGain))
                stat("SAMPLE RATE", audio.errorMessage == nil ? "44.1 kHz" : "—")
                stat("FORMAT", "M4A")
            }
            .padding(.horizontal, 10).frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                controlsCard

                Button(action: toggleRecording) {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle().stroke(audio.isRecording ? .red : green, lineWidth: 2)
                            Image(systemName: audio.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 27))
                                .foregroundStyle(audio.isRecording ? .red : green)
                        }
                        .frame(width: 112, height: 112)
                        Text(LocalizedStringKey(audio.isRecording ? "STOP" : "START"))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(2).foregroundStyle(audio.isRecording ? .red : green)
                        Text("RECORDING").font(.system(size: 8, design: .monospaced)).foregroundStyle(green)
                    }
                }
                .buttonStyle(.plain).frame(width: 124)

                Button {
                    toggleWhiteNoise(!audio.isWhiteNoisePlaying)
                } label: {
                    VStack(spacing: 12) {
                        HStack {
                            Text("PVE MODE").font(.system(size: 8, design: .monospaced))
                            Spacer()
                            Capsule()
                                .fill(audio.isWhiteNoisePlaying ? green.opacity(0.45) : Color.white.opacity(0.28))
                                .frame(width: 36, height: 21)
                                .overlay(
                                    Circle()
                                        .fill(audio.isWhiteNoisePlaying ? green : .gray)
                                        .frame(width: 15)
                                        .offset(x: audio.isWhiteNoisePlaying ? 7 : -7)
                                )
                        }
                        Divider().overlay(Color.white.opacity(0.25))
                        Text(LocalizedStringKey(audio.isWhiteNoisePlaying ? "WHITE NOISE ACTIVE" : "WHITE NOISE OFF"))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(audio.isWhiteNoisePlaying ? green : .gray)
                        EVPWaveLine()
                            .stroke(audio.isWhiteNoisePlaying ? green : .gray, lineWidth: 1.2)
                            .frame(height: 22)
                    }
                    .padding(10).frame(width: 104, height: 128)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).frame(height: 138)

            VStack(spacing: 0) {
                HStack {
                    Text("RECORDING HISTORY")
                    Spacer()
                    Text("\(recordings.count)").foregroundStyle(green)
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12).frame(height: 39)
                Divider().overlay(border)

                if recordings.isEmpty {
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(recordings, id: \.self) { recording in
                                HStack {
                                    Image(systemName: "waveform")
                                    Text(recording.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    ShareLink(item: recording) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        requestDelete(recording)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 28)
                            }
                        }
                    }
                }

                Divider().overlay(border)
                HStack {
                    footerStat("folder.fill", "TOTAL RECORDINGS", "\(recordings.count)")
                    footerStat("clock", "TOTAL DURATION", "00:00:00")
                    footerStat("externaldrive.fill", "STORAGE USED", storageText)
                }
                .frame(height: 46)
            }
            .frame(height: 194)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(border))
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(.top, 7)
        .foregroundStyle(.white)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MIC GAIN")
                Spacer()
                Text(String(format: "%.1fx", audio.softwareGain)).foregroundStyle(green)
            }
            Slider(value: Binding(
                get: { Double(audio.softwareGain) },
                set: { audio.softwareGain = Float($0) }
            ), in: 1...5).tint(green)

            HStack {
                Text("WHITE NOISE")
                Spacer()
                Text("\(Int((audio.whiteNoiseVolume * 100).rounded()))%").foregroundStyle(green)
            }
            Slider(
                value: Binding(
                    get: { Double(audio.whiteNoiseVolume) },
                    set: { audio.whiteNoiseVolume = Float($0) }
                ),
                in: 0...1
            )
            .tint(green)
            .accessibilityLabel("WHITE NOISE VOLUME")
        }
        .font(.system(size: 8, design: .monospaced))
        .padding(10).frame(width: 96, height: 128)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
    }

    private func infoCard(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title)).font(.system(size: 7, design: .monospaced))
            Text(value).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(9).frame(width: 90, height: 62, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(LocalizedStringKey(title)).font(.system(size: 6, design: .monospaced))
            Text(value).font(.system(size: 8, design: .monospaced)).foregroundStyle(green)
        }.frame(maxWidth: .infinity)
    }

    private func footerStat(_ icon: String, _ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(LocalizedStringKey(title)).font(.system(size: 5, design: .monospaced)).foregroundStyle(.gray)
            }
            Text(value).font(.system(size: 7, design: .monospaced)).foregroundStyle(green)
        }.frame(maxWidth: .infinity)
    }

    private var timeText: String {
        String(format: "%02d:%02d:%02d", elapsedSeconds / 3600, elapsedSeconds / 60 % 60, elapsedSeconds % 60)
    }

    private var audioInputStatus: String {
        audio.errorMessage == nil ? "READY" : "UNAVAILABLE"
    }

    private var storageText: String {
        let bytes = recordings.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
