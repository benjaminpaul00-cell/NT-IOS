import Combine
import SwiftUI

@MainActor
final class InvestigationState: ObservableObject {
    @Published var isSessionRunning = false
    @Published var elapsedSeconds = 0
    @Published var cameraAvailability: HardwareAvailability = .permissionRequired
    @Published var sensorAvailability: HardwareAvailability = .ready
    @Published var audioAvailability: HardwareAvailability = .permissionRequired
    @Published var isSLSEnabled = false
    @Published var usesFrontCamera = false
    @Published var savesVideo = false
    @Published var filterMode: CameraFilterMode = .normal
    @Published var output = "— — —"
    @Published private(set) var recentWords: [String] = []
    @Published var magneticDelta: Double?
    @Published var audioLevel: Double?
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?

    let camera: CameraSLSService

    private let lexicon: LexiconEngine
    private let audio: EVPAudioEngine
    private let sensors: SensorFusionEngine
    private let history: SessionHistoryStore
    private let speech: SpeechService
    private var timerTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        lexicon: LexiconEngine,
        audio: EVPAudioEngine,
        camera: CameraSLSService,
        sensors: SensorFusionEngine,
        history: SessionHistoryStore,
        speech: SpeechService
    ) {
        self.lexicon = lexicon
        self.audio = audio
        self.camera = camera
        self.sensors = sensors
        self.history = history
        self.speech = speech

        speech.onQueueDrained = { [weak self] in
            guard let self else { return }
            Task { await self.resumeMonitoringAfterSpeech() }
        }

        audio.$audioLevel
            .sink { [weak self] level in
                self?.audioLevel = Double(level)
                self?.sensors.audioLevel = Double(level)
            }
            .store(in: &cancellables)

        sensors.$latestSample
            .sink { [weak self] sample in self?.magneticDelta = sample.magneticDelta }
            .store(in: &cancellables)

        sensors.$latestTrigger
            .compactMap { $0 }
            .sink { [weak self] trigger in self?.handle(trigger: trigger) }
            .store(in: &cancellables)

        camera.$isRecording
            .assign(to: &$savesVideo)

        camera.$recordingError
            .compactMap { $0 }
            .sink { [weak self] in self?.errorMessage = $0 }
            .store(in: &cancellables)

        camera.$recordingMessage
            .compactMap { $0 }
            .sink { [weak self] in self?.confirmationMessage = $0 }
            .store(in: &cancellables)
    }

    deinit {
        timerTask?.cancel()
    }

    func startCamera() async {
        guard !camera.isRunning else { return }
        do {
            try await camera.start()
            cameraAvailability = .active
        } catch CameraSLSService.CameraError.permissionDenied {
            cameraAvailability = .permissionRequired
            errorMessage = CameraSLSService.CameraError.permissionDenied.localizedDescription
        } catch CameraSLSService.CameraError.unavailable {
            cameraAvailability = .unavailable
            errorMessage = CameraSLSService.CameraError.unavailable.localizedDescription
        } catch {
            cameraAvailability = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() async {
        let wasRecording = camera.isRecording
        await camera.stop()
        if cameraAvailability == .active { cameraAvailability = .ready }
        if wasRecording, isSessionRunning {
            do {
                try await audio.startLevelMonitoring()
                audioAvailability = .active
            } catch {
                audioAvailability = .unavailable
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleSession() {
        if isSessionRunning {
            stopSession()
        } else {
            Task { await startSession() }
        }
    }

    func setSLS(_ enabled: Bool) {
        isSLSEnabled = enabled
        camera.isSLSEnabled = enabled
    }

    func toggleVideoRecording() {
        Task {
            let startsRecording = !camera.isRecording
            do {
                if startsRecording, isSessionRunning {
                    await audio.stopLevelMonitoring()
                }
                try await camera.toggleRecording()
                if !startsRecording, isSessionRunning {
                    try await audio.startLevelMonitoring()
                    audioAvailability = .active
                }
            } catch {
                if startsRecording, isSessionRunning {
                    try? await audio.startLevelMonitoring()
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func switchCamera() {
        Task {
            do {
                try await camera.switchCamera()
                usesFrontCamera.toggle()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func suspendAudioMonitoringForEVP() async {
        guard isSessionRunning else { return }
        await audio.stopLevelMonitoring()
        audioAvailability = .ready
    }

    func resumeAudioMonitoringAfterEVP() async {
        guard isSessionRunning, !camera.isRecording else { return }
        do {
            try await audio.startLevelMonitoring()
            audioAvailability = .active
        } catch {
            audioAvailability = .unavailable
            errorMessage = error.localizedDescription
        }
    }

    private func startSession() async {
        errorMessage = nil
        do {
            try await lexicon.loadAll()
            do {
                try await audio.startLevelMonitoring()
                audioAvailability = .active
            } catch {
                audioAvailability = .unavailable
                errorMessage = error.localizedDescription
            }
            try await sensors.start()
            sensorAvailability = .active
            sensors.isSessionRunning = true
            isSessionRunning = true
            elapsedSeconds = 0
            history.beginSession()
            AnalyticsManager.shared.logToolStarted("spirit_box")
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self?.elapsedSeconds += 1
                    switch self?.elapsedSeconds {
                    case 300:
                        AnalyticsManager.shared.logSessionDuration(minutes: 5)
                    case 900:
                        AnalyticsManager.shared.logSessionDuration(minutes: 15)
                    case 1_800:
                        AnalyticsManager.shared.logSessionDuration(minutes: 30)
                    default:
                        break
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stopSession()
        }
    }

    private func stopSession() {
        if isSessionRunning {
            history.endSession()
            AnalyticsManager.shared.logToolStopped("spirit_box")
        }
        isSessionRunning = false
        sensors.isSessionRunning = false
        speech.stop()
        timerTask?.cancel()
        timerTask = nil
        Task {
            await sensors.stop()
            await audio.stopLevelMonitoring()
            sensorAvailability = .ready
            audioAvailability = .ready
        }
    }

    private func handle(trigger: SensorTrigger) {
        AnalyticsManager.shared.logTrigger(
            reason: trigger.reason,
            fieldDelta: trigger.sample.magneticDelta,
            totalEnergy: trigger.sample.totalEnergy,
            isTripleFusion: trigger.isTripleFusion
        )
        Task {
            let code = UserDefaults.standard.string(forKey: "lexicon.language") ?? AppLanguage.english.rawValue
            let language = AppLanguage(rawValue: code) ?? .english
            if let word = await lexicon.nextOutput(for: trigger.sample, language: language) {
                output = word
                recentWords.insert(word, at: 0)
                if recentWords.count > 3 {
                    recentWords.removeLast(recentWords.count - 3)
                }
                history.append(word)
                AnalyticsManager.shared.logWordEmitted(
                    word,
                    intensity: trigger.sample.totalEnergy,
                    triggerReason: trigger.reason
                )
                // AVSpeechSynthesizer can be silent while the input RemoteIO
                // graph owns the play-and-record session on a physical iPhone.
                // Release it for the speech queue, then restore it when drained.
                await audio.stopLevelMonitoring()
                audioAvailability = .ready
                speech.speak(
                    word,
                    language: language,
                    fieldDelta: trigger.sample.magneticDelta
                )
            }
        }
    }

    private func resumeMonitoringAfterSpeech() async {
        guard isSessionRunning, !camera.isRecording else { return }
        // Enhanced voices can release their output audio unit shortly after
        // didFinish. Let the route settle before rebuilding the input graph.
        try? await Task.sleep(for: .milliseconds(300))
        guard isSessionRunning, !camera.isRecording else { return }
        do {
            try await audio.startLevelMonitoring()
            audioAvailability = .active
        } catch {
            audioAvailability = .unavailable
            errorMessage = error.localizedDescription
        }
    }

    var formattedDuration: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
