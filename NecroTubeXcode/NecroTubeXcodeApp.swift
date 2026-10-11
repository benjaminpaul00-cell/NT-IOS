import SwiftUI

#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct NecroTubeXcodeApp: App {
    @StateObject private var appState: AppState

    init() {
        #if canImport(FirebaseCore)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            AnalyticsManager.shared.configureUserProperties()
            AnalyticsManager.shared.logFirstOpen()
            AnalyticsManager.shared.logSessionStart()
        }
        #endif

        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
