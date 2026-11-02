import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            InvestigationView(state: appState.investigation)
                .navigationDestination(item: $appState.presentedRoute) { route in
                    switch route {
                    case .evpRecorder:
                        EVPRecorderView(
                            audio: appState.audio,
                            onOpen: { await appState.investigation.suspendAudioMonitoringForEVP() },
                            onClose: { await appState.investigation.resumeAudioMonitoringAfterEVP() }
                        )
                    case .spiritBox:
                        SpiritBoxView(
                            radio: appState.radio,
                            onEVP: { appState.presentedRoute = .evpRecorder },
                            onHistory: { appState.presentedRoute = .history }
                        )
                    case .history:
                        SessionHistoryView(store: appState.history)
                    case .settings, .lexicon:
                        SettingsView(history: appState.history, lexicon: appState.lexicon)
                    }
                }
        }
        .environment(\.locale, Locale(identifier: appState.appLanguage.rawValue))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.refreshAppLanguage() }
        }
    }
}
