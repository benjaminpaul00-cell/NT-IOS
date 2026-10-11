@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SpeechService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    var onQueueDrained: (() -> Void)?
    private struct Request {
        let text: String
        let language: AppLanguage
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingRequests: [Request] = []
    private var activeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String, language: AppLanguage, fieldDelta: Double = 0) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        pendingRequests.append(Request(text: cleaned, language: language))
        speakNextIfNeeded()
    }

    func stop() {
        pendingRequests.removeAll()
        if activeUtterance != nil {
            synthesizer.stopSpeaking(at: .immediate)
            activeUtterance = nil
            AudioSessionCoordinator.shared.release(.speech)
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finish(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finish(utterance)
    }

    private func speakNextIfNeeded() {
        guard activeUtterance == nil, !pendingRequests.isEmpty else { return }
        let request = pendingRequests.removeFirst()

        do {
            try AudioSessionCoordinator.shared.acquire(.speech)
        } catch {
            // Keep progressing instead of permanently blocking later words.
            speakNextIfNeeded()
            return
        }

        let utterance = AVSpeechUtterance(
            string: request.text.lowercased(with: request.language.locale)
        )
        utterance.voice = preferredVoice(for: request.language)
        utterance.pitchMultiplier = 1
        utterance.rate = 0.48
        utterance.volume = 1
        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        activeUtterance = nil
        AudioSessionCoordinator.shared.release(.speech)
        if pendingRequests.isEmpty {
            onQueueDrained?()
        } else {
            speakNextIfNeeded()
        }
    }

    private func preferredVoice(for language: AppLanguage) -> AVSpeechSynthesisVoice? {
        let languageCodes: [AppLanguage: [String]] = [
            .french: ["fr-CA", "fr-FR"],
            .english: ["en-CA", "en-US", "en-GB"],
            .spanish: ["es-ES", "es-MX"],
            .german: ["de-DE"],
            .italian: ["it-IT"],
            .portuguese: ["pt-BR", "pt-PT"],
            .romanian: ["ro-RO"],
            .japanese: ["ja-JP"],
            .khmer: ["km-KH"],
            .chinese: ["zh-CN", "zh-TW"],
            .arabic: ["ar-SA"]
        ]

        let installedVoices = AVSpeechSynthesisVoice.speechVoices()
        for code in languageCodes[language, default: [language.rawValue]] {
            if let installed = installedVoices.first(where: {
                $0.language.caseInsensitiveCompare(code) == .orderedSame
            }) {
                return installed
            }
            if let systemVoice = AVSpeechSynthesisVoice(language: code) {
                return systemVoice
            }
        }
        return installedVoices.first {
            $0.language.lowercased().hasPrefix(language.rawValue.lowercased())
        }
    }
}
