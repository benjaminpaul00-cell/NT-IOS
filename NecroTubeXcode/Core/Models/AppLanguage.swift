import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case french = "fr", english = "en", spanish = "es", german = "de"
    case italian = "it", portuguese = "pt", romanian = "ro"
    case japanese = "ja", khmer = "km", chinese = "zh", arabic = "ar"

    var id: Self { self }
}
