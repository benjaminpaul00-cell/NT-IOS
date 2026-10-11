import Combine
import SwiftUI

enum AppRoute: String, Identifiable {
    case spiritBox
    case evpRecorder
    case history
    case settings
    case lexicon

    var id: Self { self }
}

@MainActor
final class AppState: ObservableObject {
    @Published var presentedRoute: AppRoute? {
        didSet {
            guard let presentedRoute else { return }
            switch presentedRoute {
            case .spiritBox:
                AnalyticsManager.shared.logToolOpened("spirit_box")
            case .evpRecorder:
                AnalyticsManager.shared.logToolOpened("evp_recorder")
            case .history:
                AnalyticsManager.shared.logToolOpened("history")
            case .settings, .lexicon:
                AnalyticsManager.shared.logToolOpened("settings")
            }
        }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "app.language")
            AnalyticsManager.shared.logLanguageSelected(appLanguage.rawValue)
        }
    }
    @Published var lexiconLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(lexiconLanguage.rawValue, forKey: "lexicon.language")
            radio.selectedLanguage = lexiconLanguage
            Task { try? await lexicon.load(language: lexiconLanguage) }
            AnalyticsManager.shared.logLanguageSelected("LEXICON_\(lexiconLanguage.rawValue)")
        }
    }

    let lexicon: LexiconEngine
    let audio: EVPAudioEngine
    let camera: CameraSLSService
    let sensors: SensorFusionEngine
    let radio: RadioSweepEngine
    let speech: SpeechService
    let history: SessionHistoryStore
    let investigation: InvestigationState

    init() {
        let defaults = UserDefaults.standard
        let storedAppLanguage = defaults.string(forKey: "app.language")
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        let storedLexiconLanguage = defaults.string(forKey: "lexicon.language")
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        appLanguage = storedAppLanguage
        lexiconLanguage = storedLexiconLanguage

        let lexicon = LexiconEngine()
        let audio = EVPAudioEngine()
        let camera = CameraSLSService()
        let sensors = SensorFusionEngine()
        let radio = RadioSweepEngine(selectedLanguage: storedLexiconLanguage)
        let speech = SpeechService()
        let history = SessionHistoryStore()

        self.lexicon = lexicon
        self.audio = audio
        self.camera = camera
        self.sensors = sensors
        self.radio = radio
        self.speech = speech
        self.history = history
        investigation = InvestigationState(
            lexicon: lexicon,
            audio: audio,
            camera: camera,
            sensors: sensors,
            history: history,
            speech: speech
        )
    }
}
