import Foundation

struct GameSession: Codable, Equatable, Sendable {
    private(set) var game: DominoGame
    private(set) var scores: [Int]
    let difficulty: Difficulty
    let targetScore: Int
    let isBlockGame: Bool
    private(set) var round = 1
    private(set) var matchID = UUID()
    private var didAwardRound = false

    init(players: Int, difficulty: Difficulty, targetScore: Int, isBlockGame: Bool) {
        self.difficulty = difficulty
        self.targetScore = targetScore
        self.isBlockGame = isBlockGame
        scores = Array(repeating: 0, count: players)
        game = DominoGame(players: players, isBlockGame: isBlockGame)
    }

    init(game: DominoGame, scores: [Int], targetScore: Int, isBlockGame: Bool,
         round: Int, matchID: String, didAwardRound: Bool) {
        self.game = game
        self.scores = scores
        self.difficulty = .medium
        self.targetScore = targetScore
        self.isBlockGame = isBlockGame
        self.round = round
        self.matchID = UUID(uuidString: matchID) ?? UUID()
        self.didAwardRound = didAwardRound
    }

    mutating func play(tileID: DominoTile.ID, on side: BoardSide) -> Bool {
        let changed = game.play(tileID: tileID, on: side)
        settleRound()
        return changed
    }

    mutating func drawOrPass() -> Bool {
        let changed = game.drawOrPass()
        settleRound()
        return changed
    }

    mutating func playComputerTurn() {
        game.playComputerTurn(difficulty: difficulty)
        settleRound()
    }

    mutating func settleRound() {
        guard game.isFinished, !didAwardRound else { return }
        if let winner = game.winner {
            scores[winner] += game.award
        }
        didAwardRound = true
    }

    var matchWinner: Int? {
        scores.firstIndex { $0 >= targetScore }
    }

    mutating func startNextRound() {
        guard game.isFinished, matchWinner == nil else { return }
        round += 1
        didAwardRound = false
        game = DominoGame(players: scores.count, isBlockGame: isBlockGame)
    }
}
