import CoreGraphics
import Foundation

protocol CameraServicing: AnyObject, Sendable {
    func requestAuthorization() async -> Bool
    func start() async throws
    func stop() async
    func switchCamera() async throws
}

protocol AudioServicing: AnyObject, Sendable {
    func requestAuthorization() async -> Bool
    func startLevelMonitoring() async throws
    func stopLevelMonitoring() async
    func startEVPRecording() async throws -> URL
    func stopEVPRecording() async throws -> URL?
}

struct SkeletonSegment: Sendable, Equatable {
    let start: CGPoint
    let end: CGPoint
    let confidence: Float
}

protocol PoseDetectionServicing: AnyObject, Sendable {
    func reset() async
}

struct RadioStation: Codable, Identifiable, Sendable, Equatable {
    let changeuuid: String
    let name: String
    let url: URL
    let country: String
    let tags: String
    let language: String
    var id: String { changeuuid }
}

protocol RadioSweepServicing: AnyObject, Sendable {
    func start(language: AppLanguage) async throws
    func stop() async
}

protocol LexiconServicing: AnyObject, Sendable {
    func load(language: AppLanguage) async throws
    func nextOutput(for sample: SensorFusionSample, language: AppLanguage) async -> String?
}

protocol SubscriptionServicing: AnyObject, Sendable {
    var hasActiveEntitlement: Bool { get async }
    func loadProducts() async throws
    func restorePurchases() async throws
}

protocol SensorFusionServicing: AnyObject, Sendable {
    func start() async throws
    func stop() async
}

protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent) async
}

enum AnalyticsEvent: Sendable, Equatable {
    case sessionStarted
    case sessionStopped
    case toolOpened(String)
}
