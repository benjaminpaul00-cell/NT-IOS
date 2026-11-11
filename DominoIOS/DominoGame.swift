import Foundation

struct DominoTile: Codable, Hashable, Identifiable, Sendable {
    let first: Int
    let second: Int

    var id: Int { min(first, second) * 7 + max(first, second) }
    var points: Int { first + second }
    var isDouble: Bool { first == second }

    func matches(_ value: Int) -> Bool { first == value || second == value }
    func flipped() -> DominoTile { DominoTile(first: second, second: first) }
}

enum BoardSide: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

enum Difficulty: Int, Codable, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
}

struct DominoGame: Codable, Equatable, Sendable {
    private(set) var hands: [[DominoTile]]
    private(set) var stock: [DominoTile]
    private(set) var board: [DominoTile] = []
    private(set) var turn: Int
    private(set) var consecutivePasses = 0
    private(set) var winner: Int?
    private(set) var award = 0
    private(set) var isFinished = false
    let isBlockGame: Bool
    private let openingTileID: Int

    init(players: Int, isBlockGame: Bool, using generator: inout some RandomNumberGenerator) {
        precondition((2...4).contains(players), "A game requires two to four players.")
        self.isBlockGame = isBlockGame
        var tiles = (0...6).flatMap { first in
            (first...6).map { DominoTile(first: first, second: $0) }
        }
        tiles.shuffle(using: &generator)
        let handSize = isBlockGame && players > 2 ? 5 : 7
        var dealtHands = Array(repeating: [DominoTile](), count: players)
        for player in 0..<players {
            for _ in 0..<handSize {
                dealtHands[player].append(tiles.removeLast())
            }
        }

        var bestRank = Int.min
        var openingID = -1
        var openingPlayer = 0
        for (player, hand) in dealtHands.enumerated() {
            for tile in hand {
                let rank = tile.isDouble ? 100 + tile.first : tile.points
                if rank > bestRank {
                    bestRank = rank
                    openingID = tile.id
                    openingPlayer = player
                }
            }
        }
        hands = dealtHands
        stock = tiles
        turn = openingPlayer
        openingTileID = openingID
    }

    init(players: Int, isBlockGame: Bool = false) {
        var generator = SystemRandomNumberGenerator()
        self.init(players: players, isBlockGame: isBlockGame, using: &generator)
    }

    init(hands: [[DominoTile]], stock: [DominoTile], board: [DominoTile], turn: Int,
         consecutivePasses: Int, winner: Int?, award: Int, isFinished: Bool,
         isBlockGame: Bool, openingTileID: Int) {
        self.hands = hands
        self.stock = stock
        self.board = board
        self.turn = turn
        self.consecutivePasses = consecutivePasses
        self.winner = winner
        self.award = award
        self.isFinished = isFinished
        self.isBlockGame = isBlockGame
        self.openingTileID = openingTileID
    }

    func isLegal(_ tile: DominoTile, on side: BoardSide) -> Bool {
        guard !board.isEmpty else { return tile.id == openingTileID }
        let end = side == .left ? board[0].first : board[board.count - 1].second
        return tile.matches(end)
    }

    func canCurrentPlayerPlay() -> Bool {
        hands[turn].contains { isLegal($0, on: .left) || isLegal($0, on: .right) }
    }

    @discardableResult
    mutating func play(tileID: DominoTile.ID, on side: BoardSide) -> Bool {
        guard !isFinished,
              let index = hands[turn].firstIndex(where: { $0.id == tileID }) else {
            return false
        }
        let tile = hands[turn][index]
        guard isLegal(tile, on: side) else { return false }
        hands[turn].remove(at: index)
        if board.isEmpty {
            board.append(tile)
        } else if side == .left {
            board.insert(tile.second == board[0].first ? tile : tile.flipped(), at: 0)
        } else {
            board.append(tile.first == board[board.count - 1].second ? tile : tile.flipped())
        }
        consecutivePasses = 0
        if hands[turn].isEmpty {
            finish(winner: turn)
        } else {
            turn = (turn + 1) % hands.count
        }
        return true
    }

    @discardableResult
    mutating func drawOrPass() -> Bool {
        guard !isFinished, !canCurrentPlayerPlay() else { return false }
        if !isBlockGame, let tile = stock.popLast() {
            hands[turn].append(tile)
        } else {
            consecutivePasses += 1
            if consecutivePasses == hands.count {
                let totals = hands.indices.map(points)
                let minimum = totals.min() ?? 0
                let candidates = totals.indices.filter { totals[$0] == minimum }
                finish(winner: candidates.count == 1 ? candidates[0] : nil)
            } else {
                turn = (turn + 1) % hands.count
            }
        }
        return true
    }

    func points(for player: Int) -> Int {
        hands[player].reduce(0) { $0 + $1.points }
    }

    mutating func playComputerTurn(difficulty: Difficulty) {
        guard !isFinished else { return }
        let options = hands[turn].flatMap { tile in
            BoardSide.allCases.compactMap { side in
                isLegal(tile, on: side) ? Move(tile: tile, side: side) : nil
            }
        }
        guard !options.isEmpty else {
            drawOrPass()
            return
        }

        let move: Move
        switch difficulty {
        case .easy:
            move = options.randomElement() ?? options[0]
        case .medium:
            move = options.max { $0.tile.points < $1.tile.points } ?? options[0]
        case .hard:
            move = options.max { score($0) < score($1) } ?? options[0]
        }
        play(tileID: move.tile.id, on: move.side)
    }

    private func score(_ move: Move) -> Double {
        let matchingEnd = board.isEmpty
            ? move.tile.first
            : (move.side == .left ? board[0].first : board[board.count - 1].second)
        let exposed = move.tile.first == matchingEnd ? move.tile.second : move.tile.first
        let opposite = board.isEmpty
            ? move.tile.second
            : (move.side == .left ? board[board.count - 1].second : board[0].first)
        var playable = 0
        var suits = Set<Int>()
        for tile in hands[turn] where tile.id != move.tile.id {
            if tile.matches(exposed) || tile.matches(opposite) {
                playable += 1
            }
            suits.formUnion([tile.first, tile.second])
        }
        var value = Double(move.tile.points + playable * 3) + Double(suits.count) * 0.5
        if move.tile.isDouble { value += 2 }
        if hands[turn].count == 1 { value += 1_000 }
        return value
    }

    private mutating func finish(winner: Int?) {
        self.winner = winner
        isFinished = true
        award = winner.map { winner in
            hands.indices
                .filter { $0 != winner }
                .reduce(0) { $0 + points(for: $1) }
        } ?? 0
    }
}

private struct Move {
    let tile: DominoTile
    let side: BoardSide
}
