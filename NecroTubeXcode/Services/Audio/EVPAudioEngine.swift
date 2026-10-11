import AVFoundation
import Combine
import Foundation

@MainActor
final class EVPAudioEngine: ObservableObject, AudioServicing {
    enum AudioError: LocalizedError {
        case permissionDenied
        case unavailableInput
        case recordingNotStarted
        case noAudioCaptured

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "L’accès au microphone est refusé."
            case .unavailableInput: "Aucune entrée audio compatible n’est disponible."
            case .recordingNotStarted: "L’enregistrement EVP n’a pas démarré."
            case .noAudioCaptured: "Aucun son n’a été capturé. Vérifiez l’entrée microphone dans le menu I/O du simulateur."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var isWhiteNoisePlaying = false
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var latestRecordingURL: URL?
    @Published var errorMessage: String?

    @Published var softwareGain: Float = 2
    @Published var whiteNoiseVolume: Float = 0.3 {
        didSet {
            let clamped = min(1, max(0, whiteNoiseVolume))
            if clamped != whiteNoiseVolume {
                whiteNoiseVolume = clamped
                return
            }
            noiseEngine.mainMixerNode.outputVolume = clamped
        }
    }

    private let inputEngine = AVAudioEngine()
    private var outputURL: URL?
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private let noiseEngine = AVAudioEngine()
    private var noiseNode: AVAudioSourceNode?
    private var tapInstalled = false
    private var isMonitoring = false
    private var isRebuildingNoise = false
    private var interruptionObserver: NSObjectProtocol?
    private var noiseConfigurationObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor [self] in
                await self.handleAudioInterruption(notification)
            }
        }

        noiseConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: noiseEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                // Let AVFAudio finish invalidating its I/O unit before the
                // graph is connected again using the new hardware format.
                try? await Task.sleep(for: .milliseconds(100))
                self.restoreWhiteNoiseAfterConfigurationChange()
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startLevelMonitoring() async throws {
        guard !isMonitoring else { return }
        guard await requestAuthorization() else { throw AudioError.permissionDenied }
        try AudioSessionCoordinator.shared.acquire(.evpInput)
        let session = AVAudioSession.sharedInstance()
        guard session.isInputAvailable else {
            AudioSessionCoordinator.shared.release(.evpInput)
            throw AudioError.unavailableInput
        }
        do {
            // A speech voice may use a different internal sample format. Clear
            // the previous RemoteIO graph before binding to the current route.
            inputEngine.stop()
            removeInputTap()
            inputEngine.reset()
            try validateInputAvailability()
            try installInputTapIfNeeded()
            if !inputEngine.isRunning {
                inputEngine.prepare()
                try inputEngine.start()
            }
            isMonitoring = true
        } catch {
            removeInputTap()
            AudioSessionCoordinator.shared.release(.evpInput)
            throw error
        }
    }

    func stopLevelMonitoring() async {
        guard isMonitoring, !isRecording else { return }
        removeInputTap()
        inputEngine.stop()
        inputEngine.reset()
        isMonitoring = false
        AudioSessionCoordinator.shared.release(.evpInput)
    }

    func startEVPRecording() async throws -> URL {
        guard !isRecording else {
            if let outputURL { return outputURL }
            throw AudioError.recordingNotStarted
        }
        guard await requestAuthorization() else { throw AudioError.permissionDenied }
        if isMonitoring {
            removeInputTap()
            inputEngine.stop()
            isMonitoring = false
            AudioSessionCoordinator.shared.release(.evpInput)
        }
        let directory = try recordingsDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let url = directory.appendingPathComponent("EVP_\(formatter.string(from: Date())).m4a")
        try AudioSessionCoordinator.shared.acquire(.evpInput)
        // Read the hardware rate only after playAndRecord is active. Bluetooth
        // HFP and route changes can alter it while changing the category.
        let sessionRate = AVAudioSession.sharedInstance().sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sessionRate > 0 ? sessionRate : 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            AudioSessionCoordinator.shared.release(.evpInput)
            throw error
        }
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            AudioSessionCoordinator.shared.release(.evpInput)
            throw AudioError.recordingNotStarted
        }
        self.recorder = recorder
        outputURL = url
        isRecording = true
        startMetering(recorder)
        return url
    }

    func stopEVPRecording() async throws -> URL? {
        guard isRecording else { return nil }
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        AudioSessionCoordinator.shared.release(.evpInput)
        let completedURL = outputURL
        outputURL = nil
        let byteCount = completedURL.flatMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } ?? 0
        guard byteCount > 128 else {
            if let completedURL {
                try? FileManager.default.removeItem(at: completedURL)
            }
            latestRecordingURL = nil
            throw AudioError.noAudioCaptured
        }
        latestRecordingURL = completedURL
        return completedURL
    }

    func startWhiteNoise() async throws {
        guard !isWhiteNoisePlaying else { return }
        try AudioSessionCoordinator.shared.acquire(.evpNoise)
        do {
            try rebuildWhiteNoiseGraph()
            isWhiteNoisePlaying = true
        } catch {
            stopWhiteNoise()
            throw error
        }
    }

    func stopWhiteNoise() {
        guard let noiseNode else {
            isWhiteNoisePlaying = false
            AudioSessionCoordinator.shared.release(.evpNoise)
            return
        }
        noiseEngine.stop()
        noiseEngine.disconnectNodeOutput(noiseNode)
        noiseEngine.detach(noiseNode)
        self.noiseNode = nil
        isWhiteNoisePlaying = false
        AudioSessionCoordinator.shared.release(.evpNoise)
    }

    func recentRecordings() -> [URL] {
        guard let directory = try? recordingsDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return urls.filter { ["wav", "m4a"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (lhs ?? .distantPast) > (rhs ?? .distantPast)
            }
            .prefix(15)
            .map { $0 }
    }

    func deleteRecording(at url: URL) throws {
        let directory = try recordingsDirectory().standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == directory else { return }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return }
        try FileManager.default.removeItem(at: candidate)
        if latestRecordingURL == candidate {
            latestRecordingURL = nil
        }
    }

    private func validateInputAvailability() throws {
        let format = inputEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioError.unavailableInput
        }
    }

    private func installInputTapIfNeeded() throws {
        guard !tapInstalled else { return }
        let input = inputEngine.inputNode
        // nil asks AVFAudio to use the current native hardware format. Passing
        // a cached explicit format after a route/session change causes -10868.
        try input.installAudioTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.process(buffer: buffer)
            }
        }
        tapInstalled = true
    }

    private func process(buffer readOnlyBuffer: AVReadOnlyAudioPCMBuffer) {
        let buffer = AVAudioPCMBuffer(copying: readOnlyBuffer)
        guard let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        let gain = softwareGain

        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let amplified = max(-1, min(1, channels[channel][frame] * gain))
                channels[channel][frame] = amplified
                peak = max(peak, abs(amplified))
            }
        }

        audioLevel = peak
    }

    private func startMetering(_ recorder: AVAudioRecorder) {
        meterTask?.cancel()
        meterTask = Task { [weak self, weak recorder] in
            while !Task.isCancelled, let recorder, recorder.isRecording {
                recorder.updateMeters()
                let decibels = recorder.averagePower(forChannel: 0)
                let normalized = pow(10, decibels / 20)
                self?.audioLevel = min(1, normalized * (self?.softwareGain ?? 1))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func rebuildWhiteNoiseGraph() throws {
        guard !isRebuildingNoise else { return }
        isRebuildingNoise = true
        defer { isRebuildingNoise = false }

        noiseEngine.stop()
        if let noiseNode {
            noiseEngine.disconnectNodeOutput(noiseNode)
            noiseEngine.detach(noiseNode)
            self.noiseNode = nil
        }
        noiseEngine.reset()

        var randomState: UInt32 = 0xA341_316C
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    randomState ^= randomState << 13
                    randomState ^= randomState >> 17
                    randomState ^= randomState << 5
                    let normalized = Float(randomState) / Float(UInt32.max)
                    samples[frame] = normalized * 2 - 1
                }
            }
            return noErr
        }

        noiseEngine.attach(source)
        try noiseEngine.connectNode(source, to: noiseEngine.mainMixerNode, format: nil)
        noiseEngine.mainMixerNode.outputVolume = whiteNoiseVolume
        noiseEngine.prepare()
        try noiseEngine.start()
        noiseNode = source
    }

    private func restoreWhiteNoiseAfterConfigurationChange() {
        guard isWhiteNoisePlaying, !isRebuildingNoise else { return }
        do {
            try AudioSessionCoordinator.shared.reactivateIfNeeded()
            try rebuildWhiteNoiseGraph()
        } catch {
            isWhiteNoisePlaying = false
            AudioSessionCoordinator.shared.release(.evpNoise)
            errorMessage = "Le bruit blanc a été interrompu par un changement audio : \(error.localizedDescription)"
        }
    }

    private func handleAudioInterruption(_ notification: Notification) async {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType),
              type == .ended else { return }

        do {
            try AudioSessionCoordinator.shared.reactivateIfNeeded()
            if isRecording, recorder?.isRecording == false {
                guard recorder?.record() == true else {
                    throw AudioError.recordingNotStarted
                }
            }
            if isWhiteNoisePlaying {
                try rebuildWhiteNoiseGraph()
            }
        } catch {
            errorMessage = "La session EVP n’a pas pu reprendre : \(error.localizedDescription)"
        }
    }

    private func removeInputTap() {
        guard tapInstalled else { return }
        inputEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
        audioLevel = 0
    }

    private func recordingsDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("EVP Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
