import AVFoundation
import UIKit

@MainActor
final class GameFeedback {
    static let shared = GameFeedback()
    private var clickPlayer: AVAudioPlayer?
    private var winPlayer: AVAudioPlayer?

    private init() {
        clickPlayer = player(named: "tile_click")
        winPlayer = player(named: "round_win")
    }

    func tile(sound: Bool, haptics: Bool) {
        if sound { clickPlayer?.play() }
        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    func win(sound: Bool, haptics: Bool) {
        if sound { winPlayer?.play() }
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func player(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }
}
