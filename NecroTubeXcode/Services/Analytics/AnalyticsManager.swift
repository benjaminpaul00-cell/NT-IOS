import Foundation
import UIKit

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

@MainActor
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private init() {}

    func configureUserProperties() {
        setUserProperty(UIDevice.current.model, name: "device_model")
        setUserProperty(Locale.current.language.languageCode?.identifier, name: "language")
        setUserProperty(Locale.current.region?.identifier, name: "country")
        setUserProperty(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, name: "app_version")
        setUserProperty("apple", name: "platform")
    }

    func setUserID(_ id: String?) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserID(id)
        #endif
    }

    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("\(name)_apple", parameters: parameters)
        #endif
    }

    func logToolOpened(_ toolName: String) {
        logEvent("\(toolName)_opened")
    }

    func logToolStarted(_ toolName: String) {
        logEvent("\(toolName)_started")
    }

    func logToolStopped(_ toolName: String) {
        logEvent("\(toolName)_stopped")
    }

    func logEVPRecordingStarted() {
        logEvent("evp_recording_started")
    }

    func logEVPRecordingFinished() {
        logEvent("evp_recording_finished")
    }

    func logRadioSweepStarted() {
        logEvent("radio_sweep_started")
    }

    func logWhiteNoiseStarted() {
        logEvent("white_noise_started")
    }

    func logWebsiteClick(source: String) {
        logEvent("website_clicked", parameters: ["source": source])
    }

    func logShareApp() {
        logEvent("share_app")
    }

    func logRateAppClicked() {
        logEvent("rate_app_clicked")
    }

    func logWatchTutorial() {
        logEvent("watch_tutorial")
    }

    func logLanguageSelected(_ language: String) {
        logEvent("language_selected", parameters: ["language": language])
    }

    func logNotificationEnabled(_ enabled: Bool) {
        logEvent("notification_enabled", parameters: ["enabled": enabled])
    }

    func logFirstOpen() {
        logEvent("first_open")
    }

    func logSessionStart() {
        logEvent("session_start")
    }

    func logSessionDuration(minutes: Int) {
        logEvent("session_\(minutes)min")
    }

    func logReturn(days: Int) {
        logEvent("return_after_\(days)_days")
    }

    func logTrigger(reason: String, fieldDelta: Double, totalEnergy: Double, isTripleFusion: Bool) {
        logEvent("trigger_event", parameters: [
            "reason": reason,
            "field_delta": fieldDelta,
            "total_energy": totalEnergy,
            "is_triple_fusion": isTripleFusion
        ])
    }

    func logWordEmitted(_ word: String, intensity: Double, triggerReason: String) {
        logEvent("word_emitted", parameters: [
            "word": word,
            "intensity": intensity,
            "trigger_reason": triggerReason
        ])
    }

    private func setUserProperty(_ value: String?, name: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserProperty(value, forName: name)
        #endif
    }
}
