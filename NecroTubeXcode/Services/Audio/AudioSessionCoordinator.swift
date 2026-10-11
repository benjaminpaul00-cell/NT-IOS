import AVFoundation
import Foundation

@MainActor
final class AudioSessionCoordinator {
    enum Client: Hashable {
        case evpInput
        case evpNoise
        case radio
        case speech
        case videoRecording
    }

    static let shared = AudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()
    private var clientCounts: [Client: Int] = [:]
    private var appliedConfiguration: Configuration?
    private var resumptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    private struct Configuration: Equatable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private init() {
        resumptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in try? self.applyConfiguration(force: true) }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            // setCategory and speaker override generate their own route-change
            // notifications. Reapplying them for those reasons can create a
            // reconfiguration loop that repeatedly stops AVAudioEngine.
            guard reason != .categoryChange, reason != .override else { return }
            Task { @MainActor [self] in try? self.applyConfiguration(force: true) }
        }
    }

    func acquire(_ client: Client) throws {
        clientCounts[client, default: 0] += 1
        do {
            try applyConfiguration()
        } catch {
            decrement(client)
            throw error
        }
    }

    func release(_ client: Client) {
        decrement(client)
        guard clientCounts.isEmpty else {
            try? applyConfiguration()
            return
        }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        appliedConfiguration = nil
    }

    func reactivateIfNeeded() throws {
        guard !clientCounts.isEmpty else { return }
        try applyConfiguration(force: true)
    }

    private func decrement(_ client: Client) {
        guard let count = clientCounts[client] else { return }
        if count <= 1 {
            clientCounts.removeValue(forKey: client)
        } else {
            clientCounts[client] = count - 1
        }
    }

    private func applyConfiguration(force: Bool = false) throws {
        let clients = Set(clientCounts.keys)
        // Keep the EVP route full-duplex for the complete lifetime of white
        // noise. Starting or stopping the microphone must not change the
        // category underneath the output AVAudioEngine.
        let needsInput = clients.contains(.evpInput) ||
            clients.contains(.evpNoise) ||
            clients.contains(.videoRecording)
        let configuration: Configuration
        if needsInput {
            let mode: AVAudioSession.Mode
            if clients.contains(.videoRecording) {
                mode = .videoRecording
            } else {
                // Keep one stable RemoteIO graph while microphone capture,
                // generated noise and speech coexist. Switching between
                // measurement and voicePrompt restarts the graph on device.
                mode = .default
            }
            configuration = Configuration(
                category: .playAndRecord,
                mode: mode,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers, .duckOthers]
            )
        } else {
            configuration = Configuration(
                category: .playback,
                mode: clients.contains(.speech) ? .voicePrompt : .spokenAudio,
                options: [.mixWithOthers, .duckOthers]
            )
        }

        guard force || configuration != appliedConfiguration else { return }
        try session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
        try session.setActive(true)
        appliedConfiguration = configuration
        if needsInput,
           session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            try session.overrideOutputAudioPort(.speaker)
        }
    }

}
