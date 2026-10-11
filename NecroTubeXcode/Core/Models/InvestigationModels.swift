import Foundation
import SwiftUI

enum CameraFilterMode: String, CaseIterable, Identifiable {
    case normal, nightVision, thermal, spectral
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .normal: "NORMAL"
        case .nightVision: "NIGHT VISION"
        case .thermal: "THERMAL"
        case .spectral: "SPECTRAL"
        }
    }
}

enum HardwareAvailability: Equatable {
    case unavailable, permissionRequired, ready, active
    case failed(String)
}

struct SensorFusionSample: Sendable, Equatable {
    let magneticX: Double
    let magneticY: Double
    let magneticZ: Double
    let magneticMagnitude: Double
    let magneticDelta: Double
    let motionEnergy: Double
    let audioEnergy: Double
    let totalEnergy: Double
}
