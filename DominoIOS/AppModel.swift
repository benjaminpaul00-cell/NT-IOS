import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case home
        case setup
        case online
        case onlineGame
        case rules
        case settings
        case profile
        case game
    }

    var route: Route = .home
    var playerCount = 4 { didSet { savePreferences() } }
    var difficulty = Difficulty.medium { didSet { savePreferences() } }
    var targetScore = 100 { didSet { savePreferences() } }
    var isBlockGame = false { didSet { savePreferences() } }
    var soundEnabled = true { didSet { savePreferences() } }
    var hapticsEnabled = true { didSet { savePreferences() } }
    var selectedAvatarIndex = 0 { didSet { savePreferences() } }
    var selectedTileID: DominoTile.ID?
    let online = OnlineGameService()
    let account = AccountService()
    private(set) var session: GameSession?
    private let saveKey = "domino.saved-session"
    private var computerTurnTask: Task<Void, Never>?

    init() {
        restorePreferences()
        restore()
    }

    func startGame() {
        computerTurnTask?.cancel()
        session = GameSession(
            players: playerCount,
            difficulty: difficulty,
            targetScore: targetScore,
            isBlockGame: isBlockGame
        )
        selectedTileID = nil
        route = .game
        save()
        scheduleComputerIfNeeded()
    }

    func navigate(to route: Route) {
        self.route = route
    }

    func resumeGame() {
        guard session != nil else { return }
        computerTurnTask?.cancel()
        route = .game
        scheduleComputerIfNeeded()
    }

    func leaveGame() {
        computerTurnTask?.cancel()
        computerTurnTask = nil
        selectedTileID = nil
        route = .home
    }

    func select(tileID: DominoTile.ID) {
        guard session?.game.turn == 0 else { return }
        selectedTileID = selectedTileID == tileID ? nil : tileID
    }

    func playSelected(on side: BoardSide) {
        let wasFinished = session?.game.isFinished == true
        guard let tileID = selectedTileID,
              session?.game.turn == 0,
              session?.play(tileID: tileID, on: side) == true else {
            return
        }
        selectedTileID = nil
        performFeedback()
        if !wasFinished, session?.game.isFinished == true {
            GameFeedback.shared.win(sound: soundEnabled, haptics: hapticsEnabled)
        }
        save()
        scheduleComputerIfNeeded()
    }

    func playSelectedOnOnlyLegalSide() {
        let legalSides = BoardSide.allCases.filter(isSelectedTileLegal)
        guard legalSides.count == 1, let side = legalSides.first else { return }
        playSelected(on: side)
    }

    func drawOrPass() {
        guard session?.game.turn == 0,
              session?.drawOrPass() == true else {
            return
        }
        save()
        performFeedback()
        scheduleComputerIfNeeded()
    }

    func performFeedback() {
        GameFeedback.shared.tile(sound: soundEnabled, haptics: hapticsEnabled)
    }

    func nextRound() {
        session?.startNextRound()
        selectedTileID = nil
        save()
        scheduleComputerIfNeeded()
    }

    func newMatch() {
        if session?.matchWinner != nil {
            AdMobService.shared.recordCompletedGame()
        }
        startGame()
    }

    func isTilePlayable(_ tile: DominoTile) -> Bool {
        guard let game = session?.game, game.turn == 0 else { return false }
        return game.isLegal(tile, on: .left) || game.isLegal(tile, on: .right)
    }

    func isSelectedTileLegal(on side: BoardSide) -> Bool {
        guard let id = selectedTileID,
              let game = session?.game,
              let tile = game.hands[0].first(where: { $0.id == id }) else {
            return false
        }
        return game.isLegal(tile, on: side)
    }

    private func scheduleComputerIfNeeded() {
        computerTurnTask?.cancel()
        guard let session, !session.game.isFinished, session.game.turn != 0 else {
            computerTurnTask = nil
            return
        }
        computerTurnTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.route == .game,
                  self.session?.game.isFinished == false,
                  self.session?.game.turn != 0 else {
                return
            }
            self.session?.playComputerTurn()
            self.save()
            self.computerTurnTask = nil
            self.scheduleComputerIfNeeded()
        }
    }

    private func save() {
        guard let session,
              let data = try? JSONEncoder().encode(session) else {
            return
        }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let restored = try? JSONDecoder().decode(GameSession.self, from: data) else {
            return
        }
        session = restored
        playerCount = restored.scores.count
        difficulty = restored.difficulty
        targetScore = restored.targetScore
        isBlockGame = restored.isBlockGame
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(playerCount, forKey: "domino.players")
        defaults.set(difficulty.rawValue, forKey: "domino.difficulty")
        defaults.set(targetScore, forKey: "domino.target")
        defaults.set(isBlockGame, forKey: "domino.block")
        defaults.set(soundEnabled, forKey: "domino.sound")
        defaults.set(hapticsEnabled, forKey: "domino.haptics")
        defaults.set(selectedAvatarIndex, forKey: "domino.avatar")
    }

    private func restorePreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "domino.players") != nil {
            playerCount = min(4, max(2, defaults.integer(forKey: "domino.players")))
        }
        if let restoredDifficulty = Difficulty(rawValue: defaults.integer(forKey: "domino.difficulty")) {
            difficulty = restoredDifficulty
        }
        if defaults.object(forKey: "domino.target") != nil {
            targetScore = defaults.integer(forKey: "domino.target") == 150 ? 150 : 100
        }
        if defaults.object(forKey: "domino.block") != nil {
            isBlockGame = defaults.bool(forKey: "domino.block")
        }
        if defaults.object(forKey: "domino.sound") != nil {
            soundEnabled = defaults.bool(forKey: "domino.sound")
        }
        if defaults.object(forKey: "domino.haptics") != nil {
            hapticsEnabled = defaults.bool(forKey: "domino.haptics")
        }
        selectedAvatarIndex = min(49, max(0, defaults.integer(forKey: "domino.avatar")))
    }
}
