import Combine
import CoreMotion
import Foundation

struct SensorTrigger: Sendable, Equatable {
    let sample: SensorFusionSample
    let magneticVector: SIMD3<Double>
    let isTripleFusion: Bool
    let reason: String
}

@MainActor
final class SensorFusionEngine: ObservableObject, SensorFusionServicing {
    enum SensorError: LocalizedError {
        case unavailable

        var errorDescription: String? { String(localized: "The magnetometer or accelerometer is unavailable.") }
    }

    @Published private(set) var latestSample = SensorFusionSample(
        magneticX: 0,
        magneticY: 0,
        magneticZ: 0,
        magneticMagnitude: 0,
        magneticDelta: 0,
        motionEnergy: 0,
        audioEnergy: 0,
        totalEnergy: 0
    )
    @Published private(set) var latestTrigger: SensorTrigger?

    var audioLevel: Double = 0
    var isSessionRunning = false
    var trialMode = false

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.necrotube.sensor-fusion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var baseline: Double?
    private var accelerationMagnitude = 9.80665
    private var lastTriggerDate = Date.distantPast
    private var cooldown: TimeInterval = 2

    func start() async throws {
        guard manager.isMagnetometerAvailable, manager.isAccelerometerAvailable else {
            throw SensorError.unavailable
        }

        manager.magnetometerUpdateInterval = 0.05
        manager.accelerometerUpdateInterval = 0.05
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let data else { return }
            let acceleration = data.acceleration
            let magnitudeG = sqrt(
                acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
            )
            Task { @MainActor [weak self] in
                self?.accelerationMagnitude = magnitudeG * 9.80665
            }
        }

        manager.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
            guard let data else { return }
            let field = data.magneticField
            Task { @MainActor [weak self] in
                self?.consumeMagneticVector(SIMD3(field.x, field.y, field.z))
            }
        }
    }

    func stop() async {
        manager.stopMagnetometerUpdates()
        manager.stopAccelerometerUpdates()
        baseline = nil
        latestTrigger = nil
    }

    private func consumeMagneticVector(_ vector: SIMD3<Double>) {
        let magnitude = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        if baseline == nil { baseline = magnitude }
        let currentBaseline = (baseline ?? magnitude) * 0.995 + magnitude * 0.005
        baseline = currentBaseline

        let delta = abs(magnitude - currentBaseline)
        let movementEnergy = max(0, accelerationMagnitude - 9.8) * 3.5
        let soundEnergy = min(15, max(0, audioLevel * 15))
        let totalEnergy = delta * 1.5 + movementEnergy + soundEnergy
        let sample = SensorFusionSample(
            magneticX: vector.x,
            magneticY: vector.y,
            magneticZ: vector.z,
            magneticMagnitude: magnitude,
            magneticDelta: delta,
            motionEnergy: movementEnergy,
            audioEnergy: soundEnergy,
            totalEnergy: totalEnergy
        )
        latestSample = sample

        let now = Date()
        guard isSessionRunning,
              now.timeIntervalSince(lastTriggerDate) >= cooldown,
              totalEnergy > 3.5 else {
            return
        }

        let tripleFusion = delta > 3 && movementEnergy > 2 && soundEnergy > 4
        lastTriggerDate = now
        cooldown = trialMode || !tripleFusion
            ? Double.random(in: 12...45)
            : Double.random(in: 3...6)
        latestTrigger = SensorTrigger(
            sample: sample,
            magneticVector: vector,
            isTripleFusion: tripleFusion,
            reason: tripleFusion ? "TRIPLE FUSION DETECTED" : "SENSOR ACTIVITY"
        )
    }
}
