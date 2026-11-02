import SwiftUI

struct SpiritBoxView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var radio: RadioSweepEngine
    let onEVP: () -> Void
    let onHistory: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 360, proxy.size.height / 760)
            ZStack {
                Color.black.ignoresSafeArea()
                SpiritBoxCanvas(
                    radio: radio,
                    selectLanguage: { appState.lexiconLanguage = $0 },
                    onEVP: onEVP,
                    onHistory: onHistory,
                    dismiss: { dismiss() }
                )
                    .frame(width: 360, height: 760)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { radio.selectedLanguage = appState.lexiconLanguage }
        .onDisappear {
            Task { await radio.stop() }
        }
        .alert("Radio Error", isPresented: Binding(
            get: { radio.errorMessage != nil },
            set: { if !$0 { radio.errorMessage = nil } }
        )) {
            Button("OK") { radio.errorMessage = nil }
        } message: {
            Text(radio.errorMessage ?? "")
        }
    }
}

private struct SpiritBoxCanvas: View {
    @ObservedObject var radio: RadioSweepEngine
    let selectLanguage: (AppLanguage) -> Void
    let onEVP: () -> Void
    let onHistory: () -> Void
    let dismiss: () -> Void

    private let green = Color(red: 0, green: 0.91, blue: 0.48)
    private let border = Color.white.opacity(0.35)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 28, weight: .light))
                        .frame(width: 46, height: 46)
                }
                Spacer()
                NecroTubeLogo().frame(width: 96, height: 46)
                Spacer()
                Menu {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            selectLanguage(language)
                        } label: {
                            if radio.selectedLanguage == language {
                                Label(language.nativeName, systemImage: "checkmark")
                            } else {
                                Text(language.nativeName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24)).frame(width: 46, height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(border, lineWidth: 1))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)

            HStack(spacing: 14) {
                Circle().fill(green).frame(width: 7, height: 7)
                Text("MAG-SCANNER ACTIVE")
                Circle().fill(green).frame(width: 7, height: 7)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(2).foregroundStyle(green)
            .frame(height: 34)

            ZStack {
                HStack {
                    statusBox
                    Spacer()
                    infoBox(title: "STATIONS", value: "\(radio.stationCount)")
                }
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        WaveLine().stroke(green, lineWidth: 1).frame(width: 27, height: 9)
                        Text("SPIRIT BOX").font(.system(size: 18, weight: .bold, design: .monospaced))
                        WaveLine().stroke(green, lineWidth: 1).frame(width: 27, height: 9)
                    }
                    Text(LocalizedStringKey(statusText)).font(.system(size: 8, design: .monospaced))
                        .tracking(1).foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 64)

            HStack(spacing: 8) {
                channelCard(index: 0, title: "CHANNEL 1")
                channelCard(index: 1, title: "CHANNEL 2")
            }
            .padding(.horizontal, 12)
            .frame(height: 246)

            VStack(spacing: 5) {
                Button {
                    Task {
                        do {
                            let enablesWhiteNoise = !radio.whiteNoiseEnabled
                            try await radio.setWhiteNoiseEnabled(enablesWhiteNoise)
                            if enablesWhiteNoise {
                                AnalyticsManager.shared.logWhiteNoiseStarted()
                            }
                        } catch {
                            radio.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        Text("WHITE NOISE").foregroundStyle(.white)
                        Spacer()
                    Text(LocalizedStringKey(radio.whiteNoiseEnabled ? "ON" : "OFF"))
                            .foregroundStyle(radio.whiteNoiseEnabled ? green : .gray)
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .buttonStyle(.plain)

                WaveLine()
                    .stroke(radio.whiteNoiseEnabled ? green : .gray, lineWidth: 1.2)
                    .frame(height: 17)

                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(radio.whiteNoiseVolume / 0.05) },
                            set: { radio.whiteNoiseVolume = Float($0) * 0.05 }
                        ),
                        in: 0...1
                    )
                    .tint(green)
                    Text("\(Int((radio.whiteNoiseVolume / 0.05 * 100).rounded()))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(green)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .padding(13)
            .frame(height: 92)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(green.opacity(0.5)))
            .padding(.horizontal, 12)

            Button(action: toggle) {
                HStack {
                    WaveLine().stroke(green, lineWidth: 1.3).frame(width: 106, height: 18)
                    Spacer()
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(green, lineWidth: 2).frame(width: 54, height: 54)
                            if radio.state == .active || radio.state == .loading {
                                Rectangle().fill(green).frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "play.fill").font(.system(size: 23)).foregroundStyle(green)
                            }
                        }
                        Text(LocalizedStringKey((radio.state == .active || radio.state == .loading) ? "STOP" : "START"))
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                    }
                    Spacer()
                    WaveLine().stroke(green, lineWidth: 1.3).frame(width: 106, height: 18)
                }
                .padding(.horizontal, 14)
                .frame(height: 82)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(border))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                bottomItem("dot.radiowaves.left.and.right", "SPIRIT BOX", active: true)
                Button(action: onEVP) {
                    bottomItem("mic.fill", "EVP RECORDER", active: false)
                }
                .buttonStyle(.plain)
                Button(action: onHistory) {
                    bottomItem("list.bullet", "HISTORY", active: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 61)

            Spacer(minLength: 0)
        }
        .padding(.top, 7)
    }

    private var statusText: String {
        switch radio.state {
        case .idle: return "IDLE"
        case .loading: return "LOADING"
        case .active: return "ACTIVE"
        case .stopped: return "STOPPED"
        case .failed: return "ERROR"
        }
    }

    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SENSORS").font(.system(size: 8, design: .monospaced))
            Text("READY").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(green)
        }
        .padding(9).frame(width: 96, height: 62, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
    }

    private func infoBox(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(LocalizedStringKey(title)).font(.system(size: 9, weight: .bold, design: .monospaced))
            Text(value).font(.system(size: 20, design: .monospaced)).foregroundStyle(green)
        }
        .frame(width: 96, height: 62)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
    }

    private func channelCard(index: Int, title: String) -> some View {
        let enabled = radio.channelEnabled[index]
        let band = radio.channelBands[index]
        let interval = radio.channelIntervalsMilliseconds[index]
        let volume = radio.channelVolumes[index]

        return VStack(spacing: 5) {
            HStack {
                Text(LocalizedStringKey(title))
                Button {
                    radio.setChannelEnabled(!enabled, channel: index)
                } label: {
                    Circle().fill(enabled ? green : .gray).frame(width: 15, height: 15)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(title)) + Text(verbatim: " ") + Text(LocalizedStringKey(enabled ? "ON" : "OFF")))
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(enabled ? green : .gray)

            HStack(spacing: 0) {
                bandButton(.am, selected: band == .am, channel: index)
                bandButton(.fm, selected: band == .fm, channel: index)
            }

            HStack(spacing: 4) {
                Button {
                    radio.setSweepInterval(milliseconds: interval + 50, channel: index)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Text("\(interval) ms")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(green)
                Button {
                    radio.setSweepInterval(milliseconds: interval - 50, channel: index)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.plain)

            Button {
                radio.toggleDirection(channel: index)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: radio.channelReversed[index] ? "arrow.left" : "arrow.right")
                    Text(LocalizedStringKey(radio.channelReversed[index] ? "REV" : "FWD"))
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(radio.channelReversed[index] ? "REVERSE" : "FORWARD")))

            Slider(
                value: Binding(
                    get: { Double(radio.channelIntervalsMilliseconds[index]) },
                    set: { radio.setSweepInterval(milliseconds: Int($0.rounded()), channel: index) }
                ),
                in: 50...400,
                step: 50
            )
            .tint(green)
            .frame(height: 15)
            .accessibilityLabel("SWEEP RATE")

            Text("SWEEP RATE").font(.system(size: 7, design: .monospaced)).tracking(1).foregroundStyle(.gray)
            Text(radio.currentStationNames[index])
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(enabled ? green : .gray)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("CURRENT STATION").font(.system(size: 7, design: .monospaced)).tracking(1).foregroundStyle(.gray)
            Divider().overlay(green)
            HStack(spacing: 5) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 11))
                Slider(
                    value: Binding(
                        get: { Double(radio.channelVolumes[index]) },
                        set: { radio.setVolume(Float($0), channel: index) }
                    ),
                    in: 0...1
                )
                .tint(green)
                Text("\(Int(volume * 100))%").font(.system(size: 8, design: .monospaced))
            }
        }
        .padding(9).foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(enabled ? 1 : 0.62)
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(enabled ? green.opacity(0.55) : border))
    }

    private func bandButton(_ band: RadioBand, selected: Bool, channel: Int) -> some View {
        Button {
            radio.setBand(band, channel: channel)
        } label: {
            Text(band.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 31)
                .foregroundStyle(selected ? .white : .gray)
                .background(selected ? green.opacity(0.8) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(border))
        }
        .buttonStyle(.plain)
    }

    private func bottomItem(_ icon: String, _ title: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20))
                Text(LocalizedStringKey(title)).font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            Text(LocalizedStringKey(active ? "COMMUNICATION" : "SESSION LOGS"))
                .font(.system(size: 6, design: .monospaced)).foregroundStyle(active ? green : .gray)
        }
        .foregroundStyle(active ? green : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? green.opacity(0.45) : border))
    }

    private func toggle() {
        Task {
            do {
                if radio.state == .active || radio.state == .loading {
                    await radio.stop()
                } else {
                    try await radio.start(language: radio.selectedLanguage)
                    AnalyticsManager.shared.logRadioSweepStarted()
                }
            } catch {
                radio.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct WaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = 24
        for index in 0...count {
            let x = rect.width * CGFloat(index) / CGFloat(count)
            let phase = CGFloat(index) * .pi / 3
            let y = rect.midY + sin(phase) * rect.height * (index.isMultiple(of: 4) ? 0.35 : 0.18)
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}
